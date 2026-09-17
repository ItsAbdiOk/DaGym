import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The calendar seams: week start, time zone, a Sunday-night workout, weekly goals of 1 and 7,
/// and the program edges (deleted routine, a deload planned twice, a week index past `weeks`).
@MainActor
@Suite("Edge data: weeks, goals and programs", .serialized)
struct EdgeDataWeeksAndProgramsTests {

    // MARK: - Helpers

    private func calendar(zone: String, mondayFirst: Bool) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        calendar.firstWeekday = mondayFirst ? 2 : 1
        return calendar
    }

    private func date(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    @discardableResult
    private func insertWorkout(
        store: WorkoutStore, exercise: ExerciseModel, date: Date, kg: Double = 60
    ) -> WorkoutModel {
        let workout = WorkoutModel(title: "Session", startedAt: date, endedAt: date.addingTimeInterval(3_000))
        store.context.insert(workout)
        let row = WorkoutExerciseModel(order: 0, exercise: exercise, workout: workout)
        store.context.insert(row)
        store.context.insert(SetLogModel(
            order: 0, kind: SetKind.working.rawValue, weightKg: kg, reps: 5, rpe: 8,
            isCompleted: true, completedAt: date, workoutExercise: row
        ))
        store.save()
        workout.stampTotals()
        store.save()
        return workout
    }

    private func bench(_ store: WorkoutStore) throws -> ExerciseModel {
        try #require(store.exerciseCatalogue().models.first { $0.name == CoachEvalLift.bench })
    }

    // MARK: - 5. Week start and time zone

    /// A workout at 23:59 on Sunday 13 Sep 2026, then `now` at 10:00 on Monday 14 Sep — in
    /// Auckland and in Los Angeles. Monday-start: the workout is last week's. Sunday-start:
    /// it opened this week.
    @Test("a Sunday 23:59 workout lands in the right week for either week start, in any zone", arguments: [
        "Pacific/Auckland", "America/Los_Angeles", "UTC"
    ])
    func sundayNightWorkout(zone: String) throws {
        for mondayFirst in [true, false] {
            let calendar = calendar(zone: zone, mondayFirst: mondayFirst)
            let store = try makeStore(seed: .exercises)
            let sunday = try date(calendar, 2026, 9, 13, 23, 59)
            let now = try date(calendar, 2026, 9, 14, 10)
            insertWorkout(store: store, exercise: try bench(store), date: sunday)

            let label = "\(zone) mondayFirst=\(mondayFirst)"
            let expectedThisWeek = mondayFirst ? 0 : 1
            let streak = Streaks.weekly(
                workoutDates: store.workoutDates(), weeklyGoal: 1, calendar: calendar, now: now
            )
            #expect(streak.thisWeekCount == expectedThisWeek, "streak \(label)")
            #expect(streak.current == 1, "a goal of 1 met last week (or this week) keeps the streak \(label)")

            let recap = store.weeklyRecap(for: now, weeklyGoal: 1, calendar: calendar)
            #expect(recap.workouts == expectedThisWeek, "recap \(label)")
            #expect(recap.workoutsDelta == (mondayFirst ? -1 : 1), "recap delta \(label)")

            let body = store.bodySeries(weeks: 4, calendar: calendar, now: now)
            #expect(body.thisWeek.workouts == expectedThisWeek, "body this week \(label)")
            #expect(body.lastWeek.workouts == 1 - expectedThisWeek, "body last week \(label)")
            #expect(body.weeklyVolume.count == 1, "weekly volume buckets \(label)")
            if let bucket = body.weeklyVolume.first {
                let weekday = calendar.component(.weekday, from: bucket.weekStart)
                #expect(weekday == calendar.firstWeekday, Comment(rawValue: label))
            }

            let hard = store.hardWeekStreak(weeklyGoal: 1, calendar: calendar, now: now)
            #expect(hard == 1, "hard weeks \(label)")

            let cells = store.consistencyCells(months: 1, now: now, calendar: calendar)
            let sundayCell = cells.first { calendar.isDate($0.date, inSameDayAs: sunday) }
            #expect((sundayCell?.sets ?? 0) > 0, "cells \(label)")

            let progress = store.milestoneProgress(weeklyGoal: 1, calendar: calendar)
            #expect(progress.allSatisfy { $0.progress >= 0 && $0.progress <= 1 }, "milestones \(label)")
        }
    }

    @Test("Home, You and the hub agree for a Sunday-start lifter with a Sunday session")
    func sundayStartScreens() throws {
        let store = try makeStore(seed: .exercises)
        let preferences = Preferences(suite: UserDefaults(suiteName: "edge-sun-\(UUID())") ?? .standard)
        preferences.weekStartsMonday = false
        preferences.weeklyGoal = 3
        let calendar = preferences.trainingCalendar
        // The most recent Sunday at 23:59 local, and now = the Monday after at 10:00.
        let today = calendar.startOfDay(for: Date())
        let daysSinceSunday = calendar.component(.weekday, from: today) - 1
        let lastSunday = try #require(calendar.date(byAdding: .day, value: -daysSinceSunday, to: today))
        let sunday = try #require(calendar.date(bySettingHour: 23, minute: 59, second: 0, of: lastSunday))
        let monday = try #require(calendar.date(byAdding: .day, value: 1, to: lastSunday))
        let now = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: monday))
        insertWorkout(store: store, exercise: try bench(store), date: sunday)

        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        let you = YouSummary.make(store: store, preferences: preferences, now: now)
        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(home.thisWeekCount == 1)
        #expect(you.thisWeekCount == 1 && hub.thisWeekCount == 1)
        #expect(you.volumeKg == 300 && hub.volumeKg == 300)
        preferences.weekStartsMonday = true
        let mondayHome = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        let mondayHub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(mondayHome.thisWeekCount == 0 && mondayHub.thisWeekCount == 0)
        #expect(mondayHub.volumeKg == 0 && mondayHub.lastWeekVolumeKg == 300)
    }

    // MARK: - 6. Weekly goal 1 and 7, changed mid-week

    @Test("weekly goals of 1 and 7, and a goal changed mid-week, never break a ring")
    func goalExtremes() throws {
        let store = try makeStore(seed: .exercises)
        let preferences = Preferences(suite: UserDefaults(suiteName: "edge-goal-\(UUID())") ?? .standard)
        let calendar = preferences.trainingCalendar
        let now = Date()
        let weekStart = try #require(calendar.dateInterval(of: .weekOfYear, for: now)?.start)
        let exercise = try bench(store)
        // Three sessions this week on three days, all before `now`.
        for day in 0..<3 {
            let date = weekStart.addingTimeInterval(TimeInterval(day) * 86_400 + 60)
            if date < now { insertWorkout(store: store, exercise: exercise, date: date) }
        }
        let trained = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: 1, calendar: calendar, now: now
        ).thisWeekCount

        preferences.weeklyGoal = 1
        let one = YouSummary.make(store: store, preferences: preferences, now: now)
        #expect(one.thisWeekCount == trained && one.weeklyGoal == 1)
        let oneHub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(oneHub.sessionsFraction == 1)
        #expect(one.streakCurrent >= 1)

        preferences.weeklyGoal = 7
        let seven = YouSummary.make(store: store, preferences: preferences, now: now)
        #expect(seven.thisWeekCount == trained && seven.weeklyGoal == 7)
        #expect(seven.streakCurrent == 0)
        let sevenHub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        let fraction = sevenHub.sessionsFraction
        #expect(abs(fraction - Double(trained) / 7) < 0.001)
        _ = store.milestoneProgress(weeklyGoal: 7, calendar: calendar)
        _ = store.deloadSuggestion(snoozedUntil: nil, weeklyGoal: 7, now: now, calendar: calendar)
        _ = store.coachCards(weeklyGoal: 7, now: now, calendar: calendar)
        _ = WidgetSnapshotWriter.snapshot(store: store, preferences: preferences, now: now)
    }

    // MARK: - 7. Program edges

    @Test("an active program whose routine was deleted keeps reading and starting")
    func programWithDeletedRoutine() throws {
        let store = try makeStore(seed: .firstLaunch)
        let program = try #require(store.adoptStarterPlan(.fullBody))
        let doomed = try #require(program.routineIDs.first)
        store.deleteRoutine(id: doomed)

        let programs = store.programs()
        #expect(programs.count == 1)
        #expect(programs.first?.isActive == true)
        #expect(store.currentWeekKind(forRoutineID: doomed) == nil, "the deleted day leaves the program")
        #expect(store.programs().first?.routineIDs.count == program.routineIDs.count - 1)
        let survivor = try #require(program.routineIDs.dropFirst().first)
        #expect(store.weekInCycle(forRoutineID: survivor) == 1)
        let session = store.startWorkout(routineID: doomed)
        #expect(session.exercises.isEmpty && session.title == "Freestyle")
        let preferences = Preferences(suite: UserDefaults(suiteName: "edge-prog-\(UUID())") ?? .standard)
        let home = HomeSnapshot.make(store: store, preferences: preferences)
        #expect(home.hasAnyRoutines)
    }

    @Test("a week index past `weeks` wraps into the defined weeks; a program past its cycles retires")
    func programWeekIndexPastWeeks() throws {
        let weeks = [
            ProgramWeekInfo(id: UUID(), index: 1, kind: .normal),
            ProgramWeekInfo(id: UUID(), index: 2, kind: .deload)
        ]
        #expect(ProgramInfo.week(at: 3, in: weeks)?.kind == .normal)
        #expect(ProgramInfo.week(at: 4, in: weeks)?.kind == .deload)
        #expect(ProgramInfo.week(at: 0, in: weeks)?.kind == .normal)
        #expect(ProgramInfo.week(at: -5, in: weeks)?.kind == .normal)
        #expect(ProgramInfo.week(at: 9, in: []) == nil)

        let store = try makeStore(seed: .firstLaunch)
        let calendar = calendar(zone: "UTC", mondayFirst: true)
        let start = try date(calendar, 2025, 1, 6, 12)
        let program = try #require(store.adoptStarterPlan(.fiveByFive, now: start))
        let farFuture = try date(calendar, 2027, 1, 4, 12)
        #expect(store.activeProgramModel(now: farFuture, calendar: calendar) == nil, "ran out of cycles")
        let listed = store.programs(now: farFuture, calendar: calendar)
        #expect(listed.first { $0.id == program.id }?.isActive == false)
        #expect(listed.first { $0.id == program.id }?.completedAt != nil)
        let id = program.id
        let descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        let model = try #require(store.fetch(descriptor).first)
        #expect(store.currentWeek(for: model, now: farFuture, calendar: calendar) == 3, "held at the last")
    }

    @Test("a deload planned twice then cancelled hands back the interrupted program, with no shim left")
    func deloadPlannedTwiceThenCancelled() throws {
        let store = try makeStore(seed: .firstLaunch)
        let program = try #require(store.adoptStarterPlan(.upperLower))
        store.planDeloadWeek()
        store.planDeloadWeek()
        #expect(store.programs().filter { $0.name == WorkoutStore.deloadProgramName }.count == 1,
                "the superseded shim is pruned, the running one stays")
        #expect(store.activeProgramModel()?.name == WorkoutStore.deloadProgramName)
        store.cancelPlannedDeloadWeek()
        let active = try #require(store.activeProgramModel())
        #expect(active.id == program.id)
        #expect(store.programs().filter { $0.name == WorkoutStore.deloadProgramName }.isEmpty)
        // Cancelling again with nothing to cancel is a no-op, not a second resume.
        store.cancelPlannedDeloadWeek()
        #expect(store.activeProgramModel()?.id == program.id)
        // And with no program to hand back to: plan, cancel, nothing active.
        store.stopProgram(id: program.id)
        store.completeProgram(id: program.id)
        store.planDeloadWeek()
        store.cancelPlannedDeloadWeek()
        #expect(store.activeProgramModel() == nil)
    }
}
