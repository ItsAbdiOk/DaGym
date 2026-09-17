import Foundation
import GymCore
import SwiftData
import SwiftUI
import Testing

@testable import DaGym

/// Every screen's summary function driven through the data states nobody seeds by hand — a
/// brand-new store, a workout with one set or none, a session still running, the fourteen-month
/// demo lifter and then that same lifter with every routine or every workout deleted. Each case
/// asserts the same thing: nothing traps, every number is finite and non-negative, and the
/// screens agree with one another about "this week".
@MainActor
@Suite("Edge data states", .serialized)
struct EdgeDataStatesTests {

    // MARK: - Helpers

    private static func isUnitInterval(_ value: Double) -> Bool { value.isFinite && value >= 0 && value <= 1 }

    private func preferences(
        weekStartsMonday: Bool = true, weeklyGoal: Int = 4, unit: WeightUnit = .kg
    ) -> Preferences {
        let preferences = Preferences(suite: UserDefaults(suiteName: "edge-\(UUID())") ?? .standard)
        preferences.weekStartsMonday = weekStartsMonday
        preferences.weeklyGoal = weeklyGoal
        preferences.weightUnit = unit
        return preferences
    }

    /// Runs every screen's read against `store` and checks the numbers are sane.
    private func sweepScreens(
        store: WorkoutStore, preferences: Preferences, now: Date, label: String
    ) {
        let calendar = preferences.trainingCalendar
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        #expect(home.streakCurrent >= 0 && home.streakLongest >= home.streakCurrent, "\(label) home streak")
        #expect(home.thisWeekCount >= 0, "\(label) home week")
        #expect(home.recoveryMap.values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "\(label) recovery")
        if let delta = home.bodyweightDeltaKg { #expect(delta.isFinite, "\(label) bw delta") }

        let you = YouSummary.make(store: store, preferences: preferences, now: now)
        #expect(you.volumeKg.isFinite && you.volumeKg >= 0, "\(label) you volume")
        #expect(you.thisWeekCount == home.thisWeekCount, "\(label) You ring agrees with Home")
        if let percent = you.volumeDeltaPercent { #expect(percent.isFinite, "\(label) you delta") }

        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(hub.volumeKg.isFinite && hub.volumeKg >= 0, "\(label) hub volume")
        #expect(hub.sessionsFraction >= 0 && hub.sessionsFraction <= 1, "\(label) hub sessions fraction")
        #expect(hub.volumeFraction >= 0 && hub.volumeFraction <= 1, "\(label) hub volume fraction")
        #expect(hub.effortFraction >= 0 && hub.effortFraction <= 1, "\(label) hub effort fraction")
        #expect(hub.musclesOnTarget >= 0 && hub.musclesBehind >= 0, "\(label) hub coverage")
        #expect(hub.headlineLifts.allSatisfy { $0.e1rmKg.isFinite && $0.e1rmKg > 0 }, "\(label) hub lifts")
        #expect(hub.thisWeekCount == home.thisWeekCount, "\(label) Progress hub ring agrees with Home")
        #expect(abs(hub.volumeKg - you.volumeKg) < 0.01, "\(label) hub volume agrees with You")

        let recap = store.weeklyRecap(for: now, weeklyGoal: preferences.weeklyGoal, calendar: calendar)
        #expect(recap.volumeKg.isFinite && recap.volumeKg >= 0, "\(label) recap")
        if let percent = recap.volumeDeltaPercent { #expect(percent.isFinite, "\(label) recap delta") }

        let body = store.bodySeries(weeks: 12, calendar: calendar, now: now)
        #expect(body.weeklyVolume.allSatisfy { $0.volumeKg.isFinite && $0.volumeKg >= 0 }, "\(label) volume")
        #expect(body.setsPerMuscle.values.allSatisfy { $0.isFinite && $0 >= 0 }, "\(label) sets per muscle")
        #expect(min(body.thisWeek.avgDurationSeconds, body.lastWeek.avgDurationSeconds) >= 0, "\(label) mins")
        let effort = store.effortSeries(weeks: 12, calendar: calendar, now: now)
        #expect(effort.weeks.allSatisfy { (0...10).contains($0.meanRPE) }, "\(label) effort")
        sweepMaps(store: store, preferences: preferences, body: body, now: now, label: label)
        sweepLists(store: store, preferences: preferences, now: now, label: label)
    }

    private func sweepMaps(
        store: WorkoutStore, preferences: Preferences, body: WorkoutStore.BodySeriesBundle, now: Date,
        label: String
    ) {
        let calendar = preferences.trainingCalendar
        let snapshot = store.recoverySnapshot(now: now, calendar: calendar)
        #expect(snapshot.perMuscle.allSatisfy { $0.spent.isFinite && $0.spent >= 0 }, "\(label) snapshot")
        let balance = MuscleMapHeroCard.Model.balance(
            bundle: body, snapshot: snapshot, horizon: .week, hardOnly: false
        )
        #expect(balance.intensity.values.allSatisfy(Self.isUnitInterval), "\(label) balance map")
        let recovery = MuscleMapHeroCard.Model.recovery(
            snapshot: snapshot,
            ramp: DGColor.recoveryRamp(differentiateWithoutColor: false, colorBlindHeatmaps: false)
        )
        #expect(recovery.intensity.values.allSatisfy(Self.isUnitInterval), "\(label) recovery map")
        let strength = MuscleMapHeroCard.Model.strength(top: store.muscleStrength(), preferences: preferences)
        #expect(strength.intensity.values.allSatisfy(Self.isUnitInterval), "\(label) strength map")
    }

    private func sweepLists(store: WorkoutStore, preferences: Preferences, now: Date, label: String) {
        let calendar = preferences.trainingCalendar
        _ = store.history()
        let stats = store.lifetimeStats()
        #expect(stats.workouts >= 0 && stats.volumeKg.isFinite && stats.volumeKg >= 0, "\(label) lifetime")
        _ = store.consistencyCells(months: 12, now: now, calendar: calendar)
        _ = store.milestoneProgress(weeklyGoal: preferences.weeklyGoal, calendar: calendar)
        for records in store.personalRecords(unit: preferences.weightUnit) {
            for record in records.records {
                let line = record.line
                #expect(!line.contains("nan") && !line.contains("inf"), "\(label) PR \(records.exerciseName)")
            }
        }
        _ = store.coachCards(weeklyGoal: preferences.weeklyGoal, now: now, calendar: calendar)
        let catalogue = store.exerciseCatalogue()
        _ = store.libraryFacets(in: catalogue)
        for info in store.exercises(in: catalogue).prefix(40) {
            if let best = info.bestE1RM { #expect(best.isFinite && best > 0, "\(label) e1RM \(info.name)") }
            _ = store.exerciseSeries(exerciseID: info.id, months: nil)
            _ = store.lastSessions(exerciseID: info.id)
        }
        _ = WidgetSnapshotWriter.snapshot(store: store, preferences: preferences, now: now)
    }

    /// A finished workout written straight into the graph at `date`, the way the demo and the
    /// sample seeder write them.
    @discardableResult
    private func insertWorkout(
        store: WorkoutStore, exercise: ExerciseModel?, date: Date, minutes: Int = 45,
        sets: [(kg: Double, reps: Int)], completed: Bool = true, finished: Bool = true
    ) -> WorkoutModel {
        let workout = WorkoutModel(
            title: "Session", startedAt: date,
            endedAt: finished ? date.addingTimeInterval(TimeInterval(minutes * 60)) : nil
        )
        store.context.insert(workout)
        let row = WorkoutExerciseModel(order: 0, exercise: exercise, workout: workout)
        store.context.insert(row)
        for (index, set) in sets.enumerated() {
            store.context.insert(SetLogModel(
                order: index, kind: SetKind.working.rawValue, weightKg: set.kg, reps: set.reps,
                isCompleted: completed, completedAt: completed ? date : nil, workoutExercise: row
            ))
        }
        store.save()
        if finished {
            workout.stampTotals()
            store.rebuildPersonalRecords()
        }
        return workout
    }

    private func demoStore() throws -> (store: WorkoutStore, now: Date, calendar: Calendar) {
        let builder = try CoachEvalStoreBuilder()
        var story = DemoLifter(builder: builder)
        try story.build()
        builder.finish()
        return (builder.store, builder.now, builder.calendar)
    }

    // MARK: - 1. Brand-new store

    @Test("a brand-new store renders every screen as empty, not broken")
    func brandNewStore() throws {
        let store = try makeStore()
        let preferences = preferences()
        let now = Date()
        sweepScreens(store: store, preferences: preferences, now: now, label: "empty")
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        #expect(!home.hasAnyRoutines)
        #expect(!home.hasSchedule)
        #expect(home.routine == nil)
        #expect(home.bodyweightKg == nil)
        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(hub.topMuscle == nil && hub.needsWork == nil && hub.callout == nil)
        #expect(hub.trackedExercises == 0)
        let you = YouSummary.make(store: store, preferences: preferences, now: now)
        #expect(you.upNext == nil)
        #expect(store.recoverySnapshot(now: now).perMuscle.isEmpty)
    }

    @Test("a first launch (library and equipment, no routines) sweeps clean")
    func firstLaunchStore() throws {
        let store = try makeStore(seed: .firstLaunch)
        sweepScreens(store: store, preferences: preferences(), now: Date(), label: "first launch")
    }

    // MARK: - 2. Tiny histories

    @Test("one workout with one set, one with none, and one still running")
    func tinyHistories() throws {
        let store = try makeStore(seed: .exercises)
        let preferences = preferences()
        let now = Date()
        let bench = try #require(store.exerciseCatalogue().models.first { $0.name == CoachEvalLift.bench })

        insertWorkout(store: store, exercise: bench, date: now.addingTimeInterval(-3_600), sets: [(60, 5)])
        sweepScreens(store: store, preferences: preferences, now: now, label: "one set")
        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(hub.thisWeekCount == 1)
        #expect(hub.volumeKg == 300)
        #expect(hub.volumeFraction == 1, "with no last week, any volume fills the ring")
        #expect(hub.trackedExercises == 1)

        // A finished workout whose only set was never ticked.
        insertWorkout(
            store: store, exercise: bench, date: now.addingTimeInterval(-7_200), sets: [(60, 5)],
            completed: false
        )
        sweepScreens(store: store, preferences: preferences, now: now, label: "zero completed sets")
        #expect(store.lifetimeStats().volumeKg == 300)

        // A crash-resume candidate: started, never ended. It must not count anywhere.
        insertWorkout(
            store: store, exercise: bench, date: now.addingTimeInterval(-600), sets: [(100, 1)],
            finished: false
        )
        sweepScreens(store: store, preferences: preferences, now: now, label: "unfinished")
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        #expect(home.thisWeekCount == 1, "the unfinished workout is not a training day")
        #expect(store.lifetimeStats().workouts == 2)
        #expect(store.personalRecords().count == 1)
    }

    @Test("a freestyle session finished with nothing logged leaves every screen sane")
    func emptyFreestyleFinish() throws {
        let store = try makeStore(seed: .exercises)
        let preferences = preferences()
        let session = store.startFreestyle()
        let summary = store.finish(session: session)
        #expect(summary.volumeKg == 0 && summary.setsDone == 0 && summary.prs.isEmpty)
        let card = ShareCardModel(summary: summary, title: "Freestyle", unit: .lb, distanceUnit: .mi)
        #expect(card.topMuscles.isEmpty)
        #expect(card.volumeText.hasSuffix("lb"))
        sweepScreens(store: store, preferences: preferences, now: Date(), label: "empty freestyle")
    }

    // MARK: - 3. The demo lifter

    @Test("the fourteen-month demo dataset sweeps clean, then without routines, then without workouts")
    func demoLifterSweeps() throws {
        let demo = try demoStore()
        let preferences = preferences()
        sweepScreens(store: demo.store, preferences: preferences, now: demo.now, label: "demo")
        let hub = ProgressHubSummary.make(store: demo.store, preferences: preferences, now: demo.now)
        #expect(hub.trackedExercises > 5)
        #expect(hub.headlineLifts.count == 2)
        #expect(hub.topMuscle != nil)
        let home = HomeSnapshot.make(store: demo.store, preferences: preferences, now: demo.now)
        #expect(home.hasSchedule && home.hasAnyRoutines)
        #expect(home.bodyweightKg != nil && home.bodyweightDeltaKg != nil)

        for routine in demo.store.routines() { demo.store.deleteRoutine(id: routine.id) }
        sweepScreens(store: demo.store, preferences: preferences, now: demo.now, label: "demo, no routines")
        let noRoutines = HomeSnapshot.make(store: demo.store, preferences: preferences, now: demo.now)
        #expect(!noRoutines.hasAnyRoutines)
        #expect(noRoutines.routine == nil, "a schedule pointing at deleted routines offers nothing")
        #expect(noRoutines.nextSessionText == nil)
        #expect(YouSummary.make(store: demo.store, preferences: preferences, now: demo.now).upNext == nil)
        // History still reads every workout, routine glyphs fall back to the deleted marker.
        #expect(demo.store.history().count > 200)
        if let first = demo.store.history().first {
            _ = demo.store.workoutDetail(id: first.id)
        }

        for record in demo.store.history() { demo.store.deleteWorkout(id: record.id) }
        sweepScreens(store: demo.store, preferences: preferences, now: demo.now, label: "demo, no workouts")
        #expect(demo.store.lifetimeStats().workouts == 0)
        #expect(demo.store.personalRecords().isEmpty)
        #expect(demo.store.recoverySnapshot(now: demo.now).perMuscle.isEmpty)
        let emptyHub = ProgressHubSummary.make(store: demo.store, preferences: preferences, now: demo.now)
        #expect(emptyHub.trackedExercises == 0 && emptyHub.topMuscle == nil)
        #expect(demo.store.achievements().isEmpty, "badges die with the workouts that earned them")
    }

    // MARK: - Seams between screens

    @Test("an Apple Health import counts as a training day on every ring, not just Home's")
    func healthImportCountsEverywhere() throws {
        let store = try makeStore(seed: .exercises)
        let preferences = preferences()
        let now = Date()
        let calendar = preferences.trainingCalendar
        let weekStart = try #require(calendar.dateInterval(of: .weekOfYear, for: now)?.start)
        let start = weekStart.addingTimeInterval(3_600)
        _ = store.importExternalWorkout(HealthExternalWorkout(
            uuid: "hk-1", start: start, end: start.addingTimeInterval(1_800), title: "Run"
        ))
        let cells = store.consistencyCells(months: 1, now: now, calendar: calendar)
        let runDay = cells.first { calendar.isDate($0.date, inSameDayAs: start) }
        #expect(runDay?.level == 1 && runDay?.minutes == 30, "the heatmap shows the day, lightest tier")
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        let you = YouSummary.make(store: store, preferences: preferences, now: now)
        #expect(home.thisWeekCount == 1)
        #expect(you.thisWeekCount == 1)
        #expect(hub.thisWeekCount == 1)
        #expect(store.history().count == 1)
        #expect(store.lifetimeStats().workouts == 1)
        let recap = store.weeklyRecap(for: now, weeklyGoal: 4, calendar: calendar)
        #expect(recap.workouts == 1)
    }
}
