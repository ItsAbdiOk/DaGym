import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore.personalRecords")
struct WorkoutStorePersonalRecordsTests {
    private func makeRoutine(store: WorkoutStore, exerciseIDs: [UUID]) -> UUID {
        let drafts = exerciseIDs.map {
            RoutineExerciseDraft(
                exerciseID: $0,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 20),
                    PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
                ]
            )
        }
        return store.saveRoutine(id: nil, name: "Push A", exercises: drafts).id
    }

    @Test("groups cached records by exercise, newest first, with a formatted line")
    func groupsByExercise() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let squat = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [bench.id, squat.id])

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 80
        session.exercises[0].sets[1].reps = 5
        session.exercises[0].sets[1].isDone = true
        session.exercises[1].sets[1].weightKg = 120
        session.exercises[1].sets[1].reps = 5
        session.exercises[1].sets[1].isDone = true
        _ = store.finish(session: session)

        let groups = store.personalRecords()

        #expect(groups.map(\.exerciseName) == ["Bench Press", "Squat"])
        let benchGroup = try #require(groups.first { $0.exerciseName == "Bench Press" })
        let record = try #require(benchGroup.records.first)
        #expect(record.kindLabel == "Estimated 1RM")
        #expect(!record.line.isEmpty)
    }

    @Test("an exercise with no cached record is not listed")
    func noRecordMeansNotListed() throws {
        let store = try makeStore()
        _ = store.createCustomExercise(
            name: "Plank", primary: [.abs], equipment: "Bodyweight", style: .bodyweightReps
        )

        let groups = store.personalRecords()
        #expect(!groups.contains { $0.exerciseName == "Plank" })
    }

    @Test("an assisted pull-up session earns an e1RM PR and a least-assistance PR")
    func assistedPullUpEarnsE1rmAndLeastAssistancePRs() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let pullUp = store.createCustomExercise(
            name: "Assisted Pull-Up", primary: [.lats], equipment: "machine", style: .assisted
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [pullUp.id])

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 0
        session.exercises[0].sets[1].reps = 6
        session.exercises[0].sets[1].assistanceKg = 20
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Assisted Pull-Up" })
        #expect(group.records.contains { $0.kindLabel == "Estimated 1RM" })
        #expect(group.records.contains { $0.kindLabel == "Least assistance" })
    }

    @Test("a weighted pull-up's e1RM reflects bodyweight + added load, not the added load alone")
    func weightedPullUpE1rmIncludesBodyweight() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80)
        let pullUp = store.createCustomExercise(
            name: "Weighted Pull-Up", primary: [.lats], equipment: "other", style: .weightedBodyweight
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [pullUp.id])

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 20
        session.exercises[0].sets[1].reps = 5
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Weighted Pull-Up" })
        let record = try #require(group.records.first { $0.kindLabel == "Estimated 1RM" })
        // "e1RM 23" would mean the added-weight-only bug; the real e1RM off bodyweight (80) + 20
        // at 5 reps is well above bodyweight.
        #expect(record.line.contains("e1RM 23") == false)
    }

    // MARK: - F1: a backfill dated before the latest session

    @Test("a backfill dated before the latest session sets the record, and a lesser later lift can't")
    func backfillBeforeLatestSessionHoldsTheRecord() throws {
        let store = try makeStore()
        let squat = store.createCustomExercise(
            name: "Back Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [squat.id])

        func log(_ session: WorkoutSession, weight: Double, reps: Int) {
            session.exercises[0].sets[1].weightKg = weight
            session.exercises[0].sets[1].reps = reps
            session.exercises[0].sets[1].isDone = true
            _ = store.finish(session: session)
        }

        // Thu: 130 × 5 (e1RM ≈ 149.8).
        log(store.startBackfill(
            date: Date().addingTimeInterval(-86_400 * 9), durationMinutes: 45, routineID: routineID
        ), weight: 130, reps: 5)
        // Fri, backfilling the Tuesday before: 140 × 5 (e1RM ≈ 161.3) — the real best.
        log(store.startBackfill(
            date: Date().addingTimeInterval(-86_400 * 11), durationMinutes: 45, routineID: routineID
        ), weight: 140, reps: 5)
        // The following Sat: 135 × 5 (e1RM ≈ 155.6) — beats Thursday, not Tuesday.
        let latest = store.startWorkout(routineID: routineID)
        latest.exercises[0].sets[1].weightKg = 135
        latest.exercises[0].sets[1].reps = 5
        latest.exercises[0].sets[1].isDone = true
        let summary = store.finish(session: latest)

        // No "PR!" for 135, because 140 is in the history.
        #expect(summary.prs.isEmpty)
        let group = try #require(store.personalRecords().first { $0.exerciseName == "Back Squat" })
        let e1rm = try #require(group.records.first { $0.kindLabel == "Estimated 1RM" })
        #expect(e1rm.line.contains("140"))
    }

    @Test("the incremental path and the replay agree, so an unrelated delete can't move a record")
    func incrementalAndReplayAgree() throws {
        let store = try makeStore()
        let squat = store.createCustomExercise(
            name: "Back Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let squatRoutine = makeRoutine(store: store, exerciseIDs: [squat.id])
        let benchRoutine = makeRoutine(store: store, exerciseIDs: [bench.id])

        func log(_ session: WorkoutSession, weight: Double, reps: Int) -> UUID? {
            session.exercises[0].sets[1].weightKg = weight
            session.exercises[0].sets[1].reps = reps
            session.exercises[0].sets[1].isDone = true
            _ = store.finish(session: session)
            return session.workoutID
        }

        _ = log(store.startBackfill(
            date: Date().addingTimeInterval(-86_400 * 9), durationMinutes: 45, routineID: squatRoutine
        ), weight: 130, reps: 5)
        _ = log(store.startBackfill(
            date: Date().addingTimeInterval(-86_400 * 11), durationMinutes: 45, routineID: squatRoutine
        ), weight: 140, reps: 5)
        _ = log(store.startWorkout(routineID: squatRoutine), weight: 135, reps: 5)
        // An unrelated bench session, then deleted — which triggers a full rebuild.
        let benchID = log(store.startWorkout(routineID: benchRoutine), weight: 60, reps: 5)

        func squatE1RMLine() throws -> String {
            let group = try #require(store.personalRecords().first { $0.exerciseName == "Back Squat" })
            return try #require(group.records.first { $0.kindLabel == "Estimated 1RM" }).line
        }
        let before = try squatE1RMLine()
        _ = store.deleteWorkout(id: try #require(benchID))
        #expect(try squatE1RMLine() == before)
    }
}

/// The lifecycle half of the PR suite: assisted and bodyweight-only styles end to end, and an
/// exercise logged twice in one workout. Split from `WorkoutStorePersonalRecordsTests` only to
/// keep either type under the 250-line body limit.
@MainActor
@Suite("WorkoutStore.personalRecords — logging styles")
struct WorkoutStorePersonalRecordStyleTests {
    private func makeRoutine(store: WorkoutStore, exerciseIDs: [UUID]) -> UUID {
        let drafts = exerciseIDs.map {
            RoutineExerciseDraft(
                exerciseID: $0,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 20),
                    PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
                ]
            )
        }
        return store.saveRoutine(id: nil, name: "Push A", exercises: drafts).id
    }

    // MARK: - F2/F3: assisted and bodyweight-only lifts, end to end

    @Test("an assisted pull-up never banks the assistance as weight lifted")
    func assistedPullUpDoesNotBankAssistanceAsLoad() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let pullUp = store.createCustomExercise(
            name: "Assisted Pull-Up", primary: [.lats], equipment: "machine", style: .assisted
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [pullUp.id])

        // The set row edits `weightKg`, and for an assisted lift that number *is* the assistance.
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 30
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Assisted Pull-Up" })
        #expect(!group.records.contains { $0.kindLabel == "Heaviest weight" })
        #expect(!group.records.contains { $0.kindLabel == "Volume" })
        #expect(group.records.contains { $0.line == "Assistance down to 30 kg" })
        // 80 − 30 = 50 kg × 8. Nothing anywhere may quote the 30 as a lifted load.
        let e1rm = try #require(group.records.first { $0.kindLabel == "Estimated 1RM" })
        #expect(e1rm.line.hasPrefix("50 × 8"))
    }

    @Test("dialling assistance down earns the PR the stale prescription used to hide")
    func assistedPRTracksTheLoggedAssistance() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let pullUp = store.createCustomExercise(
            name: "Assisted Pull-Up", primary: [.lats], equipment: "machine", style: .assisted
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [pullUp.id])

        for assistance in [30.0, 20.0] {
            let session = store.startWorkout(routineID: routineID)
            session.exercises[0].sets[1].weightKg = assistance
            session.exercises[0].sets[1].reps = 8
            session.exercises[0].sets[1].isDone = true
            _ = store.finish(session: session)
        }

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Assisted Pull-Up" })
        #expect(group.records.contains { $0.line == "Assistance down to 20 kg" })
        // 80 − 20 = 60 kg × 8, up from 50 × 8 — the second session is a genuine e1RM PR.
        let e1rm = try #require(group.records.first { $0.kindLabel == "Estimated 1RM" })
        #expect(e1rm.line.hasPrefix("60 × 8"))
    }

    @Test("an assisted exercise added mid-workout, with no prescription, still reads its own load")
    func assistedAddedMidWorkoutHasNoPhantomE1RM() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let pullUp = store.createCustomExercise(
            name: "Assisted Pull-Up", primary: [.lats], equipment: "machine", style: .assisted
        )
        let session = store.startFreestyle()
        session.exercises.append(store.autoFilledEntry(for: pullUp))
        session.exercises[0].sets[0].weightKg = 20
        session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Assisted Pull-Up" })
        let e1rm = try #require(group.records.first { $0.kindLabel == "Estimated 1RM" })
        // 80 − 20 = 60, not 80 + 20 = 100 (which estimated ~117 for someone who needs help).
        #expect(e1rm.line.hasPrefix("60 × 5"))
        #expect(!e1rm.line.contains("e1RM 117"))
    }

    @Test("a bodyweight-only lift earns no e1RM record, whatever the lifter weighs")
    func bodyweightOnlyLiftEarnsNoE1RM() throws {
        let store = try makeStore()
        _ = store.logBodyweight(kg: 80)
        let airSquat = store.createCustomExercise(
            name: "Bodyweight Squat", primary: [.quads], equipment: "bodyweight", style: .bodyweightReps
        )
        let routineID = makeRoutine(store: store, exerciseIDs: [airSquat.id])

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 0
        session.exercises[0].sets[1].reps = 12
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let group = try #require(store.personalRecords().first { $0.exerciseName == "Bodyweight Squat" })
        #expect(!group.records.contains { $0.kindLabel == "Estimated 1RM" })
        #expect(group.records.contains { $0.line == "12 reps bodyweight" })
    }

    @Test("a bodyweight-only lift earns no e1RM whether or not a weigh-in exists")
    func bodyweightOnlyIsTheSameWithAndWithoutAWeighIn() throws {
        for logsBodyweight in [true, false] {
            let store = try makeStore()
            if logsBodyweight { _ = store.logBodyweight(kg: 80) }
            let airSquat = store.createCustomExercise(
                name: "Bodyweight Squat", primary: [.quads], equipment: "bodyweight",
                style: .bodyweightReps
            )
            let routineID = makeRoutine(store: store, exerciseIDs: [airSquat.id])
            let session = store.startWorkout(routineID: routineID)
            session.exercises[0].sets[1].weightKg = 0
            session.exercises[0].sets[1].reps = 12
            session.exercises[0].sets[1].isDone = true
            _ = store.finish(session: session)

            let group = store.personalRecords().first { $0.exerciseName == "Bodyweight Squat" }
            #expect(group?.records.contains { $0.kindLabel == "Estimated 1RM" } == false)
        }
    }

    // MARK: - F5: the same exercise logged twice in one workout

    @Test("an exercise logged twice in one workout: the summary sees the heavier second entry")
    func sameExerciseTwiceIsFullyVisible() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let session = store.startFreestyle()
        session.exercises.append(store.autoFilledEntry(for: bench, setCount: 1))
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 8
        session.exercises[0].sets[0].isDone = true
        // Same exercise again later in the session, heavier.
        session.exercises.append(store.autoFilledEntry(for: bench, setCount: 1))
        session.exercises[1].sets[0].weightKg = 100
        session.exercises[1].sets[0].reps = 3
        session.exercises[1].sets[0].isDone = true
        let summary = store.finish(session: session)

        // One row for the exercise, and it reports the 100 × 3 the PR banner celebrates.
        let changes = summary.e1rmChanges.filter { $0.exerciseID == bench.id }
        #expect(changes.count == 1)
        let current = try #require(changes.first?.current)
        let e1rm100x3 = 108.2874
        #expect(abs(current - e1rm100x3) < 0.01)
        #expect(summary.prs.contains { $0.exerciseName == "Bench Press" })
    }

    @Test("an exercise logged twice in one workout charts both entries, not just the first")
    func sameExerciseTwiceIsCharted() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let session = store.startFreestyle()
        session.exercises.append(store.autoFilledEntry(for: bench, setCount: 1))
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 8
        session.exercises[0].sets[0].isDone = true
        session.exercises.append(store.autoFilledEntry(for: bench, setCount: 1))
        session.exercises[1].sets[0].weightKg = 100
        session.exercises[1].sets[0].reps = 3
        session.exercises[1].sets[0].isDone = true
        _ = store.finish(session: session)

        let bundle = store.exerciseSeries(exerciseID: bench.id, months: nil)
        let expectedVolume: Double = 640 + 300 // 80 × 8 plus 100 × 3
        #expect(bundle.topSet.map(\.value) == [100])
        #expect(bundle.volume.map(\.value) == [expectedVolume])
        // The sparkline reads the heavier set too, not the 80 × 8 that happened to be logged first.
        let sparkline = store.sparklineSeries(exerciseID: bench.id)
        #expect(sparkline.count == 1)
        #expect((sparkline.first?.1 ?? 0) > 105)
    }
}
