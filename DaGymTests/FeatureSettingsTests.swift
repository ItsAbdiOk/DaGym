import Foundation
import GymCore
import SwiftData
import SwiftUI
import Testing
import UserNotifications

@testable import DaGym

/// A fake `RestNotificationCenter` that just records calls — same shape every scheduler test
/// file uses (`RestNotificationSchedulerTests`, `TrainingNotificationSchedulerTests`).
private final class FakeNotificationCenter: RestNotificationCenter {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []

    func add(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }
}

@MainActor
private func makeStore() throws -> WorkoutStore {
    let container = try ModelContainer.dagym(inMemory: true)
    return WorkoutStore(context: ModelContext(container))
}

// MARK: - WorkoutDayReminderScheduler (Batch B3 item 3)

@MainActor
@Suite("WorkoutDayReminderScheduler")
struct WorkoutDayReminderSchedulerTests {
    /// A fixed Monday (2026-01-05) at 06:00, so every day in the horizon is deterministic and
    /// the 07:00 reminder for "today" is still in the future.
    private static func monday() -> Date {
        var components = DateComponents(year: 2026, month: 1, day: 5, hour: 6)
        components.calendar = calendar()
        return calendar().date(from: components) ?? Date()
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeRoutine(_ store: WorkoutStore, name: String) -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: "\(name) Exercise", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
        )
        return store.saveRoutine(id: nil, name: name, exercises: [draft])
    }

    private func weekdays(of center: FakeNotificationCenter) -> [Int] {
        center.addedRequests.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday
        }
    }

    @Test("schedules a dated reminder per planned day in the horizon, at the configured hour")
    func schedulesPerPlannedDay() throws {
        let store = try makeStore()
        let push = makeRoutine(store, name: "Push A")
        store.saveSchedule(WeeklySchedule(days: [.monday: push.id, .thursday: push.id]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = true
        preferences.workoutDayReminderHour = 7
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)

        scheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: Self.calendar(), now: Self.monday()
        )

        // 28 days of horizon: four Mondays and four Thursdays.
        #expect(center.addedRequests.count == 8)
        for request in center.addedRequests {
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(!trigger.repeats)
            #expect(trigger.dateComponents.hour == 7)
        }
        #expect(Set(weekdays(of: center)) == Set([Weekday.monday.rawValue, Weekday.thursday.rawValue]))
        #expect(center.addedRequests.first?.content.body.contains("Push A") == true)
    }

    /// Finding 6: the old version built one repeating trigger per *weekday*, so a session moved to
    /// Saturday with `WeeklySchedule.dateOverrides` still buzzed on Wednesday and stayed silent on
    /// Saturday. Dated triggers read the same override the schedule editor shows.
    @Test("a session moved to another date moves its reminder with it")
    func movedSessionMovesItsReminder() throws {
        let store = try makeStore()
        let calendar = Self.calendar()
        let monday = Self.monday()
        let push = makeRoutine(store, name: "Push A")
        var schedule = WeeklySchedule(days: [.wednesday: push.id])
        let wednesday = try #require(calendar.date(byAdding: .day, value: 2, to: monday))
        let saturday = try #require(calendar.date(byAdding: .day, value: 5, to: monday))
        schedule.moved(date: wednesday, toRoutines: [])
        schedule.moved(date: saturday, toRoutines: [push.id])
        store.saveSchedule(schedule)

        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = true
        preferences.workoutDayReminderHour = 7
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)

        scheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: calendar, now: monday
        )

        let days = center.addedRequests.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.day
        }
        // This week: nothing on the 7th (Wednesday), a reminder on the 10th (Saturday).
        #expect(!days.contains(7))
        #expect(days.contains(10))
        // The recurring Wednesday is untouched from next week on.
        #expect(days.contains(14))
    }

    @Test("disabled: cancels every identifier and schedules nothing")
    func disabledSchedulesNothing() throws {
        let store = try makeStore()
        let push = makeRoutine(store, name: "Push A")
        store.saveSchedule(WeeklySchedule(days: [.monday: push.id]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = false
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)

        scheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: Self.calendar(), now: Self.monday()
        )

        #expect(center.addedRequests.isEmpty)
        #expect(center.removedIdentifiers.count == 1)
    }

    @Test("rescheduling twice never leaves duplicate requests: each call cancels every identifier first")
    func reschedulingCancelsFirst() throws {
        let store = try makeStore()
        let push = makeRoutine(store, name: "Push A")
        store.saveSchedule(WeeklySchedule(days: [.monday: push.id, .friday: push.id]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = true
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)

        scheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: Self.calendar(), now: Self.monday()
        )
        scheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: Self.calendar(), now: Self.monday()
        )

        #expect(center.removedIdentifiers.count == 2)
        // Every slot the horizon can use, plus the seven legacy weekday identifiers.
        #expect(center.removedIdentifiers[1].count >= WorkoutDayReminderScheduler.horizonDays)
        #expect(center.removedIdentifiers[1].contains("workout-day-reminder-2"))
    }

    @Test("changing the schedule after enabling: the next reschedule reflects the new days only")
    func reflectsScheduleChanges() throws {
        let store = try makeStore()
        let push = makeRoutine(store, name: "Push A")
        store.saveSchedule(WeeklySchedule(days: [.monday: push.id]))
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutDayReminderEnabled = true
        let center = FakeNotificationCenter()
        let scheduler = WorkoutDayReminderScheduler(center: center)
        scheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: Self.calendar(), now: Self.monday()
        )
        let firstBatch = center.addedRequests.count

        store.saveSchedule(WeeklySchedule(days: [.wednesday: push.id]))
        scheduler.rescheduleAll(
            store: store, preferences: preferences, calendar: Self.calendar(), now: Self.monday()
        )

        let second = Array(weekdays(of: center).dropFirst(firstBatch))
        #expect(!second.isEmpty)
        #expect(Set(second) == Set([Weekday.wednesday.rawValue]))
    }
}

// MARK: - Reminder permission (finding 5)

private struct FakeNotificationAuthorization: NotificationAuthorizing {
    /// What iOS reports before anything is asked, and what the prompt resolves to.
    var current: UNAuthorizationStatus
    var afterRequest: UNAuthorizationStatus
    let requests = RequestCounter()

    func status() async -> UNAuthorizationStatus { current }

    func request() async -> UNAuthorizationStatus {
        await requests.bump()
        return afterRequest
    }
}

/// Counts `request()` calls across the actor hop `NotificationAuthorizing` requires.
private final class RequestCounter: @unchecked Sendable {
    private(set) var count = 0
    var isEmpty: Bool { count < 1 }
    @MainActor func bump() { count += 1 }
}

/// Finding 5: the reminder toggles flipped a preference and rescheduled without ever asking for
/// permission. A lifter who skipped onboarding's "Allow" turned on "Workout day reminder", watched
/// the toggle stay on, and never received anything — iOS drops scheduled requests for an
/// unauthorised app on the floor.
@MainActor
@Suite("Reminder permission")
struct ReminderPermissionStateTests {
    @Test("turning a reminder on asks for permission")
    func turningOnRequests() async {
        let authorization = FakeNotificationAuthorization(
            current: .notDetermined, afterRequest: .authorized
        )
        let state = ReminderPermissionState(authorization: authorization)

        await state.toggled(on: true)

        #expect(authorization.requests.count == 1)
        #expect(state.status == .authorized)
        #expect(!state.isDenied)
    }

    @Test("turning a reminder off only re-reads; it never prompts")
    func turningOffDoesNotRequest() async {
        let authorization = FakeNotificationAuthorization(
            current: .authorized, afterRequest: .authorized
        )
        let state = ReminderPermissionState(authorization: authorization)

        await state.toggled(on: false)

        #expect(authorization.requests.isEmpty)
        #expect(state.status == .authorized)
    }

    @Test("a denied answer is surfaced, so Settings can say notifications are off in iOS")
    func deniedIsSurfaced() async {
        let authorization = FakeNotificationAuthorization(
            current: .notDetermined, afterRequest: .denied
        )
        let state = ReminderPermissionState(authorization: authorization)

        await state.toggled(on: true)

        #expect(state.isDenied)
    }

    @Test("permission revoked in iOS Settings after the fact shows up on the next read")
    func revokedLaterIsPickedUp() async {
        let authorization = FakeNotificationAuthorization(current: .denied, afterRequest: .denied)
        let state = ReminderPermissionState(authorization: authorization)
        #expect(!state.isDenied) // nothing read yet

        await state.refresh()

        #expect(state.isDenied)
    }
}

/// `SettingsView.body` rebuilds `RemindersSettingsSection` on every stepper tap up there. While
/// `permission` was a plain stored property each rebuild got a fresh, unread `.notDetermined`
/// state and the "Notifications are off" row vanished until Settings was reopened; `@State`
/// keeps the first instance for the life of the view.
@MainActor
@Suite("Reminders section state")
struct RemindersSectionStateTests {
    @Test("the permission state survives the section being rebuilt")
    func permissionIsViewState() {
        let section = RemindersSettingsSection(permission: ReminderPermissionState())
        let permission = Mirror(reflecting: section).children.first { $0.label == "_permission" }
        #expect(permission?.value is State<ReminderPermissionState>)
    }
}

/// Picking a unit in the CSV preview re-parses the file. `.sheet(item:)` keys the sheet on `id`,
/// so a re-parse that minted a new UUID dismissed the sheet and presented a new one mid-tap.
@Suite("CSV import preview identity")
struct FeatureImportSheetTests {
    @Test("a re-parse keeps the pending import's identity")
    func reparseKeepsIdentity() {
        let preview = ImportPreview(
            source: .strong, workouts: [], setsCount: 0, unmatchedExerciseNames: [], problems: []
        )
        let pending = PendingCSVImport(preview: preview, csv: "Date,Exercise")
        var lbPreview = preview
        lbPreview.weightUnit = .lb

        let reparsed = pending.reparsed(preview: lbPreview)

        #expect(reparsed.id == pending.id)
        #expect(reparsed.csv == pending.csv)
        #expect(reparsed.preview.weightUnit == .lb)
    }
}

// MARK: - TrainingNotificationScheduler integration (Batch B3 item 3)

@MainActor
@Suite("TrainingNotificationScheduler + workout-day reminder")
struct TrainingNotificationWorkoutDayTests {
    @Test("rescheduleAll also reschedules the workout-day reminder through the injected scheduler")
    func rescheduleAllIncludesWorkoutDayReminder() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routine = store.saveRoutine(
            id: nil, name: "Push A",
            exercises: [RoutineExerciseDraft(
                exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
            )]
        )
        store.saveSchedule(WeeklySchedule(days: [.tuesday: routine.id]))
        let defaults = UserDefaults(suiteName: #function) ?? .standard
        defaults.removePersistentDomain(forName: #function)
        let preferences = Preferences(suite: defaults)
        preferences.workoutDayReminderEnabled = true
        preferences.workoutDayReminderHour = 9

        let workoutDayCenter = FakeNotificationCenter()
        let workoutDayScheduler = WorkoutDayReminderScheduler(center: workoutDayCenter)
        let scheduler = TrainingNotificationScheduler(
            center: FakeNotificationCenter(), calendar: .current,
            workoutDayReminderScheduler: workoutDayScheduler
        )

        scheduler.rescheduleAll(store: store, preferences: preferences)

        // One per Tuesday inside the 28-day horizon, all naming the routine and the hour.
        #expect(!workoutDayCenter.addedRequests.isEmpty)
        for request in workoutDayCenter.addedRequests {
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.dateComponents.weekday == Weekday.tuesday.rawValue)
            #expect(trigger.dateComponents.hour == 9)
            #expect(request.content.body.contains("Push A"))
        }
    }
}

// MARK: - WorkoutStore.wipeAllData (Batch B3 item 26)

@MainActor
@Suite("WorkoutStore.wipeAllData")
struct WorkoutStoreWipeAllDataTests {
    @Test("deletes every model and resets preferences to their shipped defaults")
    func wipesEverythingAndResetsPreferences() throws {
        let store = try makeStore()
        store.context.insert(ExerciseModel(name: "Bench Press", isCustom: true))
        store.saveSchedule(WeeklySchedule(days: [.monday: UUID()]))
        store.save()
        #expect(!((try? store.context.fetch(FetchDescriptor<ExerciseModel>())) ?? []).isEmpty)
        #expect(!((try? store.context.fetch(FetchDescriptor<ScheduleModel>())) ?? []).isEmpty)

        let defaults = UserDefaults(suiteName: #function) ?? .standard
        defaults.removePersistentDomain(forName: #function)
        let preferences = Preferences(suite: defaults)
        preferences.weeklyGoal = 6
        preferences.effortTrackingEnabled = false
        preferences.appearance = .dark
        preferences.bodyFigure = .male
        preferences.weighInBeforeWorkout = true
        preferences.workoutDayReminderEnabled = true

        store.wipeAllData(preferences: preferences, effects: .inert)

        // The user's own rows are gone; the library is re-seeded so they land on a fresh
        // install rather than an empty app that only fills in on the next cold launch.
        let exercises = (try? store.context.fetch(FetchDescriptor<ExerciseModel>())) ?? []
        #expect(!exercises.contains { $0.isCustom })
        #expect(exercises.contains(where: { $0.seedID != nil }))
        #expect(((try? store.context.fetch(FetchDescriptor<ScheduleModel>())) ?? []).isEmpty)
        #expect(preferences.weeklyGoal == 4)
        #expect(preferences.effortTrackingEnabled)
        #expect(preferences.appearance == .system)
        #expect(preferences.bodyFigure == .neutral)
        #expect(preferences.weighInBeforeWorkout == false)
        #expect(preferences.workoutDayReminderEnabled == false)
    }

    /// Guards `WorkoutStore.wipeAllData`'s explicit, unrolled delete list: if a model is ever
    /// added to `DaGymSchema.mainModels` without a matching eraser, this fails instead of
    /// silently leaving that model's rows behind after a reset. Derived from the real list on
    /// both sides — the old literal-vs-literal `== 19` guarded nothing.
    @Test("every mainModels type has an eraser in wipeAllData's delete list")
    func mainModelsCountMatchesDeleteList() {
        #expect(WorkoutStore.mainModelErasers.count == DaGymSchema.mainModels.count)
    }

    /// Every preference the app persists is written back to its shipped default. Derived from
    /// `Preferences` itself via a fresh instance, so a new preference that `resetToDefaults`
    /// forgets shows up here rather than surviving a "reset everything".
    @Test("reset leaves every preference at the value a fresh install has")
    func resetRestoresEveryPreference() throws {
        let store = try makeStore()
        let name = "resetRestoresEveryPreference"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(suite: defaults)
        preferences.voiceSpeakBackOnHeadphones = false
        preferences.voiceAutoLogEnabled = true
        preferences.sampleDataMode = true
        preferences.coachModelID = "openai/gpt-5"
        preferences.coachReviewerModelID = nil
        preferences.coachChatConsentGiven = true

        store.wipeAllData(preferences: preferences, effects: .inert)

        let fresh = Preferences(suite: UserDefaults(suiteName: name + "-fresh") ?? .standard)
        #expect(preferences.voiceSpeakBackOnHeadphones == fresh.voiceSpeakBackOnHeadphones)
        #expect(preferences.voiceAutoLogEnabled == fresh.voiceAutoLogEnabled)
        #expect(preferences.sampleDataMode == fresh.sampleDataMode)
        #expect(preferences.coachModelID == fresh.coachModelID)
        #expect(preferences.coachReviewerModelID == fresh.coachReviewerModelID)
        #expect(preferences.coachReviewerModelID == CoachChatConfiguration.defaultReviewerModelID)
        #expect(preferences.coachChatConsentGiven == fresh.coachChatConsentGiven)
    }

    /// The side effects a wipe has outside the store. Each one left something behind that
    /// outlived the reset: notifications kept firing for routines that no longer exist, the
    /// widget kept showing the old session, the calendar kept events whose ids the wipe had
    /// just deleted (orphaning them forever), and the Hevy key stayed in the Keychain.
    @Test("reset clears notifications, the widget snapshot, calendar events and stored secrets")
    func resetClearsSideEffects() throws {
        let store = try makeStore()
        store.saveScheduleEventIDs(["2026-01-05": "event-1", "2026-01-07": "event-2"])
        let defaults = UserDefaults(suiteName: #function) ?? .standard
        defaults.removePersistentDomain(forName: #function)

        var cancelled = false
        var clearedWidget = false
        var removedSecrets = false
        var deletedEvents: [String] = []
        let effects = ResetSideEffects(
            cancelNotifications: { cancelled = true },
            clearWidgetSnapshot: { clearedWidget = true },
            removeSecrets: { removedSecrets = true },
            deleteCalendarEvents: { deletedEvents = $0.sorted() }
        )

        store.wipeAllData(preferences: Preferences(suite: defaults), effects: effects)

        #expect(cancelled)
        #expect(clearedWidget)
        #expect(removedSecrets)
        #expect(deletedEvents == ["event-1", "event-2"])
    }
}
