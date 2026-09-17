import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Property test for the voice *apply* path: any transcript, against any shape of live session,
/// through `VoiceLogController.process` → auto-log or review card → `confirmReview` (with the
/// card as parsed, with hostile edits, and with a stale card whose exercise has since been
/// removed) → undo. A trap anywhere here is a crash with the mic button under the lifter's
/// thumb. Iteration count follows `FuzzIterations` (`DAGYM_TEST_FUZZ_ITERATIONS`).
@MainActor
@Suite("Fuzz: voice apply path", .serialized)
struct FuzzVoiceApplyTests {
    nonisolated static let iterations = FuzzIterations.count

    /// xorshift64*, duplicated from `GymCoreTests` (test targets don't share sources).
    struct RNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
        mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
        mutating func bool() -> Bool { next() & 1 == 1 }
        mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }
    }

    nonisolated static let vocabulary: [String] = [
        "bench", "press", "squat", "plank", "run", "treadmill", "pull", "ups", "dips", "one", "two",
        "three", "eight", "ten", "twenty", "sixty", "hundred", "thousand", "point", "and", "a", "half",
        "0", "1", "8", "60", "100", "225", "102.5", "1e6", "nan", "-1", "99999999999999999999", "٣",
        "x", "for", "at", "reps", "sets", "of", "kg", "lb", "plates", "per", "side", "seconds",
        "minutes", "k", "miles", "done", "next", "same", "again", "undo", "scrap", "that", "rate",
        "rpe", "rir", "correction", "actually", "swap", "add", "remove", "drop", "set", "warm", "up",
        "rest", "note", "what", "was", "last", "time", "my", "pr", "🏋️", "", "-", ".", "\u{0}"
    ]

    nonisolated static let hostileEdits: [Double?] = [
        nil, 0, -1, -0.0, .nan, .infinity, -.infinity, 1e308, 5e-324, 2.5, 60, 1_000_000, 4999, 5001
    ]
    nonisolated static let hostileReps: [Int?] = [nil, 0, -1, 1, 8, 100, 101, .max, .min]

    private static func soup(_ rng: inout RNG) -> String {
        let count = rng.int(10)
        return (0..<count).map { _ in rng.pick(vocabulary) }.joined(separator: " ")
    }

    private static func exercise(
        _ name: String, style: ExerciseInfo.LoggingStyle = .weightReps
    ) -> ExerciseInfo {
        ExerciseInfo(
            name: name, primary: [.chest], equipment: "Barbell", incrementKg: 2.5, bar: .olympic,
            loggingStyle: style
        )
    }

    /// Every session shape the apply path has to survive: nothing at all, an exercise with no
    /// sets, everything already done, a superset pair, a duplicated exercise, cardio and timed.
    private static func session(_ rng: inout RNG) -> WorkoutSession {
        let bench = exercise("Bench Press")
        let plank = exercise("Plank", style: .timedHold)
        let run = exercise("Treadmill Run", style: .cardio)
        let dips = exercise("Dips", style: .bodyweightReps)
        let done = SetEntry(weightKg: 100, reps: 8, isDone: true)
        func timed(_ seconds: Int) -> SetEntry { SetEntry(weightKg: 0, reps: 0, targetSeconds: seconds) }
        let shapes: [[WorkoutExerciseEntry]] = [
            [],
            [WorkoutExerciseEntry(exercise: bench, sets: [])],
            [WorkoutExerciseEntry(exercise: bench, sets: [done])],
            [WorkoutExerciseEntry(exercise: bench, sets: [SetEntry(weightKg: 0, reps: 0)])],
            [
                WorkoutExerciseEntry(
                    exercise: bench, sets: [SetEntry(weightKg: 100, reps: 8)], supersetGroup: 1
                ),
                WorkoutExerciseEntry(
                    exercise: dips, sets: [SetEntry(weightKg: 0, reps: 10)], supersetGroup: 1
                )
            ],
            [
                WorkoutExerciseEntry(exercise: bench, sets: [done]),
                WorkoutExerciseEntry(exercise: bench, sets: [SetEntry(weightKg: 100, reps: 8)])
            ],
            [WorkoutExerciseEntry(exercise: plank, sets: [timed(60)])],
            [WorkoutExerciseEntry(exercise: run, sets: [timed(1500)])],
            [
                WorkoutExerciseEntry(exercise: bench, sets: [SetEntry(weightKg: 100, reps: 8)]),
                WorkoutExerciseEntry(exercise: plank, sets: [SetEntry(weightKg: 0, reps: 0)]),
                WorkoutExerciseEntry(exercise: run, sets: [SetEntry(weightKg: 0, reps: 0)]),
                WorkoutExerciseEntry(exercise: dips, sets: [SetEntry(weightKg: 0, reps: 10)])
            ]
        ]
        let session = WorkoutSession(
            title: "Fuzz", subtitle: "", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: rng.pick(shapes)
        )
        session.restHaptics = false
        return session
    }

    /// One transcript through the whole path. Returns nothing; any trap fails the test.
    private static func run(_ transcript: String, rng: inout RNG, store: WorkoutStore) {
        let workout = session(&rng)
        let preferences = VoiceLogFixtures.preferences(
            unit: rng.bool() ? .kg : .lb, autoLog: rng.bool()
        )
        let controller = VoiceLogFixtures.controller(FakeSpeechRecognizer())
        var undos: [UndoAction] = []
        let context = VoiceLogTurnContext(
            session: workout, store: store, preferences: preferences, undo: { undos.append($0) }
        )
        let confidence: Double? = rng.pick([nil, 0, 0.5, 0.95, 1, .nan])
        controller.process(transcript: transcript, recognitionConfidence: confidence, turn: context)

        if case .reviewing(var card) = controller.state {
            if rng.bool() {
                card.weightKg = rng.pick(hostileEdits)
                card.reps = rng.pick(hostileReps)
                card.durationSeconds = rng.pick(hostileReps)
            }
            if rng.int(4) == 0, !workout.exercises.isEmpty {
                // The exercise was removed while the card was up.
                workout.exercises.removeAll { $0.id == card.entryID }
            }
            controller.confirmReview(card, session: workout, store: store, preferences: preferences) {
                undos.append($0)
            }
        }
        if rng.bool(), !workout.exercises.isEmpty {
            // Sets vanish before the undo fires.
            workout.exercises[0].sets.removeAll()
        }
        for undo in undos { undo.undo() }
        for undo in undos { undo.undo() } // Twice: undo is idempotent, never a second write.
        controller.cancel()
    }

    @Test("random transcripts against random session shapes never trap")
    func randomTranscripts() throws {
        let store = try makeStore()
        var rng = RNG(seed: 0xA991_0001)
        for _ in 0..<Self.iterations {
            Self.run(Self.soup(&rng), rng: &rng, store: store)
        }
    }

    @Test("hand-picked utterances against every session shape never trap")
    func hostileUtterances() throws {
        let store = try makeStore()
        var rng = RNG(seed: 0xA991_0002)
        let utterances = [
            "", "done", "next", "undo", "same again", "eight at a hundred", "100 for 8",
            "three sets of eight at sixty", "1000000 sets of 8 at 60", "plank sixty seconds",
            "ran 5 k in 25 minutes", "dips ten", "bench 1e6 for 8", "bench nan for nan",
            "drop set 60 for 12", "warm up set 40 for 10", "rate that a 9", "bench 0 for 0",
            "squat 100 for 8", "correction 8 reps", "rest two minutes", "what was last time"
        ]
        for utterance in utterances {
            for _ in 0..<9 { Self.run(utterance, rng: &rng, store: store) }
        }
    }

    @Test("a stale review card whose exercise is gone is refused, not applied by index")
    func staleReviewCardIsRefused() throws {
        let store = try makeStore()
        let workout = VoiceLogFixtures.singleSetSession()
        let preferences = VoiceLogFixtures.preferences()
        let controller = VoiceLogFixtures.controller(FakeSpeechRecognizer())
        controller.process(
            transcript: "100 for 8", recognitionConfidence: nil,
            turn: VoiceLogTurnContext(session: workout, store: store, preferences: preferences) { _ in }
        )
        guard case .reviewing(let card) = controller.state else {
            Issue.record("expected a review card, got \(controller.state)")
            return
        }
        workout.exercises.removeAll()
        controller.confirmReview(card, session: workout, store: store, preferences: preferences) { _ in
            Issue.record("a card for a removed exercise must never log")
        }
        #expect(controller.state == .error(.unsupportedCommand))
    }

    @Test("\u{201C}done\u{201D} on an exercise with no sets is refused, not indexed")
    func doneWithNoSetsIsRefused() throws {
        let store = try makeStore()
        let workout = VoiceLogFixtures.session([
            WorkoutExerciseEntry(exercise: VoiceLogFixtures.exercise(), sets: [])
        ])
        let preferences = VoiceLogFixtures.preferences(autoLog: true)
        let controller = VoiceLogFixtures.controller(FakeSpeechRecognizer())
        controller.process(
            transcript: "done", recognitionConfidence: 0.99,
            turn: VoiceLogTurnContext(session: workout, store: store, preferences: preferences) { _ in
                Issue.record("nothing to complete, nothing to undo")
            }
        )
        #expect(controller.state == .error(.unsupportedCommand))
    }
}
