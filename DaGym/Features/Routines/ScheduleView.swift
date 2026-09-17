import GymCore
import SwiftData
import SwiftUI

/// The Schedule segment of the Train tab: one row per weekday of the current training week —
/// the day, the routines planned on it (a "Push A + Arms" day merges them in order when
/// started) or "Rest", and an accent "Move" / "Add" that opens the day's editor. Under it, a
/// footnote saying what calendar sync is actually doing, and the row into the exercise
/// library. Saves after every change and, when `Preferences.calendarSyncEnabled` is on,
/// mirrors the plan onto the "DaGym" calendar via `CalendarSyncService` (plan.md §6.8).
struct ScheduleView: View {
    /// Pushes a You-hub destination (the library row, the "Settings" link) onto Train's stack.
    var onPush: (YouDestination) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var routines: [RoutineInfo] = []
    @State private var schedule = WeeklySchedule()
    @State private var moveRequest: MoveRequest?
    @State private var syncProblem: String?
    @State private var exerciseCount = 0
    @State private var customCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrainRowGroup {
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    let weekday = orderedWeekdays[index]
                    ScheduleDayRow(
                        date: date, weekday: weekday, isToday: date == today,
                        isLast: index == weekDates.count - 1, routines: routines,
                        planned: routines(on: date), templateIDs: schedule.dayRoutines[weekday] ?? [],
                        onToggle: { toggle($0, on: weekday) },
                        onRest: { rest(weekday) },
                        onMove: date >= today ? { beginMove(date: date) } : nil
                    )
                }
            }
            footnote
                .padding(.horizontal, DGSpace.s1)
                .padding(.top, 10)
            libraryRow
                .padding(.top, DGSpace.s4)
        }
        .task { refresh() }
        .refreshOnStoreChange(refresh)
        .sheet(item: $moveRequest) { request in
            MoveSessionSheet(
                request: request, calendar: preferences.trainingCalendar,
                onMove: { performMove(request, to: $0) }
            )
        }
    }

    /// Says what actually happened. It used to claim the plan was synced whenever the toggle
    /// was on — including when calendar access had been denied and every sync was failing
    /// silently behind a `try?`.
    @ViewBuilder
    private var footnote: some View {
        if let syncProblemMessage {
            Text(syncProblemMessage)
                .font(.system(size: 12))
                .foregroundStyle(DGColor.danger)
        } else if preferences.calendarSyncEnabled {
            Text("Calendar sync is on. Sessions land at \(startTime) in your \"DaGym\" calendar.")
                .font(.system(size: 12))
                .foregroundStyle(DGColor.ink3)
        } else {
            HStack(spacing: 4) {
                Text("Calendar sync is off.")
                    .font(.system(size: 12))
                    .foregroundStyle(DGColor.ink3)
                Button("Turn it on in Settings") { onPush(.settings) }
                    .buttonStyle(.dgControl)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DGColor.coralText)
            }
        }
    }

    /// "Exercise library / 412 exercises · 9 of yours" — pushes `LibraryView`.
    private var libraryRow: some View {
        Button { onPush(.library) } label: {
            HStack(spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exercise library")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                    Text(libraryMeta)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                TrainChevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dgCard(radius: 16, padding: DGSpace.s4)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.dgCard)
        .accessibilityIdentifier(A11yID.trainLibrary)
    }

    private var libraryMeta: String {
        let total = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        return customCount == 0 ? total : "\(total) · \(customCount) of yours"
    }

    /// "18:00" in the lifter's locale — `scheduledStartHour` is the hour synced sessions start at.
    private var startTime: String {
        let calendar = preferences.trainingCalendar
        let hour = preferences.scheduledStartHour
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today)
        return (date ?? today).formatted(.dateTime.hour().minute())
    }

    /// This screen's own sync result first; otherwise what the last launch / foreground sync
    /// recorded on `CalendarSyncCoordinator.status` (`@Observable`, so `body` tracks it).
    private var syncProblemMessage: String? {
        syncProblem ?? CalendarSyncCoordinator.status.problemMessage
    }

    private var orderedWeekdays: [Weekday] { Weekday.ordered(mondayFirst: preferences.weekStartsMonday) }

    private var today: Date { preferences.trainingCalendar.startOfDay(for: Date()) }

    /// The dates of the current training week in `orderedWeekdays` order — Monday first for a
    /// Monday-start lifter — read with `preferences.trainingCalendar`, like every other schedule
    /// read (`UnitEnvironment`'s single-calendar rule), so Sunday lands in the right week.
    private var weekDates: [Date] {
        let calendar = preferences.trainingCalendar
        let today = today
        let interval = calendar.dateInterval(of: .weekOfYear, for: today)
        let start = interval?.start ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func routines(on date: Date) -> [RoutineInfo] {
        schedule.routineIDs(on: date, calendar: preferences.trainingCalendar)
            .compactMap { id in routines.first { $0.id == id } }
    }

    private func refresh() {
        routines = store.routines()
        schedule = store.schedule()
        exerciseCount = store.fetchCount(Self.liveExercises(customOnly: false))
        customCount = store.fetchCount(Self.liveExercises(customOnly: true))
    }

    /// Live rows only — the same `mergedIntoID == nil` rule as `WorkoutStore.isLive` and the
    /// library's own count — as a predicate so counting never materialises the library.
    private static func liveExercises(customOnly: Bool) -> FetchDescriptor<ExerciseModel> {
        if customOnly {
            return FetchDescriptor<ExerciseModel>(
                predicate: #Predicate { $0.mergedIntoID == nil && $0.isCustom }
            )
        }
        return FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.mergedIntoID == nil })
    }

    private func toggle(_ routineID: UUID, on weekday: Weekday) {
        if (schedule.dayRoutines[weekday] ?? []).contains(routineID) {
            schedule.removeRoutine(routineID, from: weekday)
        } else {
            schedule.addRoutine(routineID, to: weekday)
        }
        persist()
    }

    private func rest(_ weekday: Weekday) {
        schedule.setRoutines([], on: weekday)
        persist()
    }

    private func beginMove(date: Date) {
        let planned = routines(on: date)
        guard !planned.isEmpty else { return }
        moveRequest = MoveRequest(
            sourceDate: date, routineIDs: planned.map(\.id), routineName: RoutineInfo.joinedNames(planned)
        )
    }

    private func performMove(_ request: MoveRequest, to newDate: Date) {
        schedule.moved(date: request.sourceDate, toRoutines: [])
        schedule.moved(date: newDate, toRoutines: request.routineIDs)
        persist()
    }

    private func persist() {
        store.saveSchedule(schedule)
        WidgetSnapshotWriter.refresh(store: store, preferences: preferences)
        // Workout-day reminders are dated, so a schedule edit invalidates every pending one.
        // Without this they only caught up on the next launch.
        TrainingNotificationScheduler().rescheduleAll(store: store, preferences: preferences)
        syncCalendar()
    }

    /// `CalendarSyncCoordinator` owns the serialising chain (a settings toggle and a schedule
    /// edit could otherwise sync concurrently over the same event ids) and reports refusals
    /// instead of swallowing them.
    private func syncCalendar() {
        guard !LaunchFlags.isTesting else { return }
        Task {
            let outcome = await CalendarSyncCoordinator.sync(store: store, preferences: preferences)
            syncProblem = outcome.problemMessage
        }
    }
}

/// A pending "move this session to a new date" request, presented as a sheet.
struct MoveRequest: Identifiable {
    let id = UUID()
    var sourceDate: Date
    var routineIDs: [UUID]
    var routineName: String
}

extension RoutineInfo {
    /// "Push A + Arms" — how a multi-routine day reads everywhere it's named.
    static func joinedNames(_ routines: [RoutineInfo]) -> String {
        routines.map(\.name).joined(separator: " + ")
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        ScrollView {
            ScheduleView(onPush: { _ in }).padding()
        }
        .environment(WorkoutStore(context: container.mainContext))
        .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
