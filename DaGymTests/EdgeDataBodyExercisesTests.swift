import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Bodyweight edges (goal at/above current, one reading, delete with undo), exercise edges
/// (no muscles, deleted mid-history, 0 kg, timed holds and cardio in every stats path) and lb
/// throughout, switched mid-session.
@MainActor
@Suite("Edge data: body, exercises and units", .serialized)
struct EdgeDataBodyExercisesTests {

    private func preferences(unit: WeightUnit = .kg) -> Preferences {
        let preferences = Preferences(suite: UserDefaults(suiteName: "edge-b-\(UUID())") ?? .standard)
        preferences.weightUnit = unit
        preferences.distanceUnit = DistanceUnit.matching(unit)
        return preferences
    }

    // MARK: - 8. Bodyweight

    @Test("goal equal to, above and below the current weight; one reading only")
    func bodyweightGoalStates() throws {
        let store = try makeStore()
        let preferences = preferences()
        let now = Date()
        store.logBodyweight(kg: 80, date: now.addingTimeInterval(-60))
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        #expect(home.bodyweightKg == 80)
        #expect(home.bodyweightDeltaKg == nil, "one reading has nothing to compare against")

        let atGoal = BodyweightGoal.status(currentKg: 80, goalKg: 80, deltaKg: nil, unit: .kg)
        #expect(atGoal.isReached && atGoal.remainingKg == 0 && atGoal.trend == .flat)
        let nearlyLb = BodyweightGoal.status(currentKg: 80.02, goalKg: 80, deltaKg: -0.5, unit: .lb)
        #expect(nearlyLb.isReached, "0.02 kg rounds away in either unit")
        let gaining = BodyweightGoal.status(currentKg: 80, goalKg: 85, deltaKg: 1.2, unit: .kg)
        #expect(!gaining.isReached && gaining.trend == .toward && gaining.remainingKg == 5)
        let gainingAway = BodyweightGoal.status(currentKg: 80, goalKg: 85, deltaKg: -1.2, unit: .kg)
        #expect(gainingAway.trend == .away)
        let losing = BodyweightGoal.status(currentKg: 80, goalKg: 75, deltaKg: -1.2, unit: .kg)
        #expect(losing.trend == .toward && losing.remainingKg == 5)

        // A second reading 31 days back gives Home its delta; Health rows never reach the chart's
        // manual series but do count as the latest reading.
        store.logBodyweight(kg: 82, date: now.addingTimeInterval(-31 * 86_400))
        store.logBodyweight(kg: 79.5, date: now, source: "health")
        let withDelta = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        #expect(withDelta.bodyweightKg == 79.5)
        #expect(withDelta.bodyweightDeltaKg.map { abs($0 + 2.5) < 0.001 } == true)
        #expect(store.manualBodyweightSeries().count == 2)
        #expect(store.bodyweightSeries().count == 3)
        #expect(store.recentBodyMeasurements().count == 3)
    }

    @Test("the Body card's 30-day move is the number Home's tile shows")
    func bodyCardDeltaMatchesHome() throws {
        let store = try makeStore()
        let preferences = preferences()
        let now = Date()
        store.logBodyweight(kg: 82, date: now.addingTimeInterval(-31 * 86_400))
        store.logBodyweight(kg: 81, date: now.addingTimeInterval(-20 * 86_400))
        store.logBodyweight(kg: 80, date: now)
        let home = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        let card = BodyweightCard.thirtyDayDeltaKg(series: store.bodyweightSeries())
        #expect(home.bodyweightDeltaKg.map { abs($0 + 2) < 0.001 } == true)
        #expect(card.map { abs($0 + 2) < 0.001 } == true, "not −1 against the first in-window reading")
        let recent = store.bodyweightSeries().filter { $0.date > now.addingTimeInterval(-25 * 86_400) }
        #expect(BodyweightCard.thirtyDayDeltaKg(series: recent) == nil, "nothing 30 days back, no move")
    }

    @Test("deleting a reading returns a snapshot, and restoring it puts the same row back once")
    func deleteAndRestoreReading() throws {
        let store = try makeStore()
        let now = Date()
        let older = store.logBodyweight(kg: 82, date: now.addingTimeInterval(-86_400))
        let latest = store.logBodyweight(kg: 80, date: now)
        let token = store.changeToken

        let snapshot = try #require(store.deleteBodyMeasurement(id: latest.id))
        #expect(snapshot.kg == 80 && snapshot.id == latest.id && snapshot.source == "manual")
        #expect(store.changeToken > token, "the Body chart refreshes on the change token")
        #expect(store.latestBodyMeasurement()?.id == older.id)
        #expect(store.recentBodyMeasurements().count == 1)
        #expect(store.deleteBodyMeasurement(id: latest.id) == nil, "already gone")

        store.restoreBodyMeasurement(snapshot)
        store.restoreBodyMeasurement(snapshot)
        #expect(store.recentBodyMeasurements().count == 2, "a double undo restores once")
        #expect(store.latestBodyMeasurement()?.id == latest.id)
        #expect(store.latestBodyMeasurement()?.bodyweightKg == 80)
    }

    // MARK: - 9. Exercises

    @Test("a custom exercise with no muscles, a 0 kg set, a timed hold and a run reach every stats path")
    func oddExercisesInEveryStatsPath() throws {
        let store = try makeStore(seed: .exercises, units: .fixed(weight: .lb))
        let preferences = preferences(unit: .lb)
        let now = Date()
        let noMuscles = store.createCustomExercise(
            name: "Mystery", primary: [], equipment: "other", style: .weightReps
        )
        let hold = store.createCustomExercise(
            name: "Plank", primary: [.abs], equipment: "bodyweight", style: .timedHold
        )
        let run = store.createCustomExercise(
            name: "Run", primary: [.quads], equipment: "other", style: .cardio
        )
        let pushUp = store.createCustomExercise(
            name: "Push-up", primary: [.chest], equipment: "bodyweight", style: .bodyweightReps
        )

        let session = oddSession(store: store, exercises: [noMuscles, hold, run, pushUp])
        let summary = store.finish(session: session, unit: .lb)
        #expect(summary.volumeKg == 0)
        #expect(summary.setsDone == 4)
        #expect(summary.distanceMeters == 5_000)
        #expect(summary.musclesHit.values.allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(summary.prs.allSatisfy { !$0.line.contains("nan") })

        let card = ShareCardModel(summary: summary, title: "Odd", unit: .lb, distanceUnit: .mi)
        #expect(card.distanceText?.contains("mi") == true)
        #expect(card.volumeText == "0 lb")
        #expect(card.topMuscles.allSatisfy { $0.share.isFinite && $0.share > 0 && $0.share <= 1 })

        for exercise in [noMuscles, hold, run, pushUp] {
            let series = store.exerciseSeries(exerciseID: exercise.id, months: nil)
            #expect(series.e1rm.allSatisfy { $0.value.isFinite }, Comment(rawValue: exercise.name))
            let name = Comment(rawValue: exercise.name)
            #expect(series.volume.allSatisfy { $0.value.isFinite && $0.value >= 0 }, name)
            #expect(series.e1rmTrendDeltaKg.isFinite, Comment(rawValue: exercise.name))
            let lines = store.lastSessions(exerciseID: exercise.id)
            #expect(lines.count == 1, Comment(rawValue: exercise.name))
            #expect(lines.allSatisfy { !$0.contains("nan") && !$0.contains("inf") }, name)
            if let model = store.fetchExerciseModel(id: exercise.id) {
                let info = store.exerciseInfo(for: model)
                #expect(info.sessions == 1, Comment(rawValue: exercise.name))
                #expect(info.bestE1RM.map(\.isFinite) ?? true, Comment(rawValue: exercise.name))
            }
        }
        #expect(store.lastSessions(exerciseID: hold.id).first == "1:00")
        #expect(store.lastSessions(exerciseID: run.id).first?.contains("mi") == true)
        #expect(store.lastSessions(exerciseID: pushUp.id).first == "20")

        let records = store.personalRecords(unit: .lb)
        #expect(records.flatMap(\.records).allSatisfy { !$0.line.contains("nan") })
        _ = store.recoverySnapshot(now: now)
        _ = store.muscleStrength()
        _ = store.bodySeries(weeks: 4, now: now)
        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(hub.volumeKg == 0 && hub.thisWeekCount == 1)
        _ = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        _ = store.libraryFacets(in: store.exerciseCatalogue())
        #expect(store.exercises(in: store.exerciseCatalogue(), customOnly: true).count == 4)
    }

    /// A 0 kg × 10, a 1:00 hold, a 5 km run in 25:00 and 20 push-ups, one set each, all ticked.
    private func oddSession(store: WorkoutStore, exercises: [ExerciseInfo]) -> WorkoutSession {
        let session = store.startFreestyle()
        for exercise in exercises {
            session.exercises.append(store.autoFilledEntry(for: exercise))
        }
        session.exercises[0].sets[0].weightKg = 0
        session.exercises[0].sets[0].reps = 10
        session.exercises[1].sets[0].durationSeconds = 60
        session.exercises[2].sets[0].durationSeconds = 1_500
        session.exercises[2].sets[0].distanceMeters = 5_000
        session.exercises[3].sets[0].reps = 20
        for index in session.exercises.indices { session.exercises[index].sets[0].isDone = true }
        return session
    }

    @Test("history keeps reading after the custom exercise it references is renamed, then deleted")
    func renamedAndDeletedExerciseInHistory() throws {
        let store = try makeStore(seed: .exercises)
        let preferences = preferences()
        let now = Date()
        let custom = store.createCustomExercise(
            name: "Cable Thing", primary: [.lats], equipment: "cable", style: .weightReps
        )
        let session = store.startFreestyle()
        session.exercises.append(store.autoFilledEntry(for: custom))
        session.exercises[0].sets[0].weightKg = 40
        session.exercises[0].sets[0].reps = 12
        session.exercises[0].sets[0].isDone = true
        let workoutID = try #require(session.workoutID)
        _ = store.finish(session: session)
        #expect(store.personalRecords().count == 1)

        store.updateCustomExercise(id: custom.id, fields: CustomExerciseFields(
            name: "Cable Row", primary: [.lats, .biceps], equipment: "cable", style: .weightReps
        ))
        #expect(store.workoutDetail(id: workoutID).exercises.first?.exercise.name == "Cable Row")
        #expect(store.personalRecords().first?.exerciseName == "Cable Row")

        #expect(store.deleteCustomExercise(id: custom.id))
        let detail = store.workoutDetail(id: workoutID)
        #expect(detail.exercises.first?.exercise.name == "Deleted exercise")
        #expect(store.lifetimeStats().volumeKg == 480, "history totals survive the delete")
        #expect(store.history().count == 1)
        store.rebuildPersonalRecords()
        #expect(store.personalRecords().isEmpty, "no records for an exercise that no longer exists")
        let hub = ProgressHubSummary.make(store: store, preferences: preferences, now: now)
        #expect(hub.thisWeekCount == 1 && hub.trackedExercises == 0)
        _ = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        _ = store.exerciseSeries(exerciseID: custom.id, months: nil)
        #expect(store.lastSessions(exerciseID: custom.id).isEmpty, "no exercise, no detail screen to feed")
        let export = BackupService.export(context: store.context, preferences: preferences)
        #expect(export.workouts.count == 1)
    }

    // MARK: - 4. lb and miles throughout, switched mid-session

    @Test("lb + miles: formatting, plates, PR lines, coach facts in kg, and a mid-session switch")
    func poundsThroughout() throws {
        let store = try makeStore(seed: .exercises, units: .fixed(weight: .lb))
        let preferences = preferences(unit: .lb)
        let bench = try #require(store.exercises(matching: CoachEvalLift.bench).first)
        let session = store.startFreestyle()
        session.exercises.append(store.autoFilledEntry(for: bench))
        session.exercises[0].sets[0].weightKg = WeightUnit.lb.toKg(135)
        session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets[0].isDone = true
        let summary = store.finish(session: session, unit: .lb)
        #expect(summary.prs.first?.line.contains("135 × 5") == true)
        #expect(summary.prs.first?.line.contains("61.25") == false)
        let card = ShareCardModel(summary: summary, title: "Bench", unit: .lb, distanceUnit: .mi)
        #expect(card.volumeText == "675 lb")

        #expect(store.lastSessions(exerciseID: bench.id).first == "135 × 5")
        let info = store.exerciseInfo(for: try #require(store.fetchExerciseModel(id: bench.id)))
        #expect(info.bestSet == "135×5")
        #expect(store.personalRecords(unit: .lb).first?.records.first?.line.contains("135") == true)
        #expect(preferences.formatWeight(kg: WeightUnit.lb.toKg(135)) == "135")
        #expect(preferences.formatVolume(kg: summary.volumeKg) == "675")
        #expect(preferences.formatDistance(meters: 1_609.344, decimals: 1) == "1.0 mi")

        // Plate maths on a 45 lb bar with a lb stock: 135 is a 45 a side, exactly.
        let load = PlateCalculator.load(
            target: WeightUnit.lb.toKg(135), bar: WeightUnit.lb.defaultBar,
            plates: WeightUnit.plateStock(for: .lb)
        )
        guard case .exact(let exact) = load else {
            Issue.record("135 lb should load exactly: \(load)")
            return
        }
        #expect(exact.perSide.count == 1)
        #expect(abs(WeightUnit.lb.display(kg: exact.perSide[0]) - 45) < 0.01)

        // The chart series and the coach read the same session in kg however the lifter logs.
        let e1rm = store.exerciseSeries(exerciseID: bench.id, months: nil).e1rm.last?.value
        #expect(e1rm.map { $0 > 60 && $0 < 80 } == true, "an e1RM in kg, never 135-ish pounds")
        #expect(store.coachInput(weeklyGoal: 4).lifts.allSatisfy { $0.e1rmTrend.allSatisfy { $0 < 200 } })

        // Switching to kg mid-session: the stored number is unchanged, the strings follow.
        store.units = .fixed(weight: .kg)
        preferences.weightUnit = .kg
        #expect(store.lastSessions(exerciseID: bench.id).first == "61.25 × 5")
        #expect(preferences.formatWeight(kg: WeightUnit.lb.toKg(135)) == "61.25")
        let strength = MuscleMapHeroCard.Model.strength(top: store.muscleStrength(), preferences: preferences)
        #expect(strength.detail.contains("kg"))
    }
}
