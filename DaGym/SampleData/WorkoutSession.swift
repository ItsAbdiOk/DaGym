import Foundation
import GymCore

/// State of one in-progress session. Drives the Active Workout screen. Split out of
/// `Models.swift` to keep that file under the 400-line lint cap — everything it needs
/// (`SetEntry`, `WorkoutExerciseEntry`, `PersonalRecordInfo`, `RestState`, `Haptics`) lives
/// elsewhere in this module.
@Observable
@MainActor
final class WorkoutSession {
    var title: String
    var subtitle: String
    var startedAt: Date
    var exercises: [WorkoutExerciseEntry]
    var effortScale: Effort.Scale = .rpe
    /// True for a session logged after the fact via "Log a Past Workout".
    var isBackfilled: Bool
    /// The `WorkoutModel` this session is backed by, once persisted.
    var workoutID: UUID?
    /// Free-text note for the whole session, persisted to `WorkoutModel.notes`.
    var notes: String = ""

    // Rest timer
    var restRemaining: Int = 0
    var restTotal: Int = 0
    /// "Next <exercise name>" / "Last set done" — set whenever the next step isn't a plain
    /// weight × reps set. When it *is*, `restNextWeightKg`/`restNextReps` carry the raw data
    /// and the view (which has unit `Preferences`) builds the "Next 82.5 × 8" text.
    var restNextLabel: String = ""
    var restNextWeightKg: Double?
    var restNextReps: Int?
    var isResting: Bool { restRemaining > 0 }
    /// Notified on every tick with the new `restRemaining`, so UI-only concerns (rest sound,
    /// screen flash) can live outside this UI-free model. Set by `ActiveWorkoutView`.
    var onRestTick: ((Int) -> Void)?
    /// Notified on every rest-state change (start/adjust/skip/natural end), so the Live
    /// Activity + lock screen notification (`Features/LiveActivity`) can mirror it without this
    /// UI-free model knowing about ActivityKit. Set by `ActiveWorkoutView+LiveActivity.swift`.
    var onRestStateChange: ((RestState) -> Void)?
    private var restExerciseName = ""
    private var restSetNumber = 0
    private var restSetCount = 0

    // PR banner
    var prBanner: PersonalRecordInfo?

    init(
        title: String, subtitle: String, startedAt: Date, exercises: [WorkoutExerciseEntry],
        isBackfilled: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.startedAt = startedAt
        self.exercises = exercises
        self.isBackfilled = isBackfilled
    }

    /// Timed-hold live timer, or nil when no hold is in progress.
    var timedHold: TimedHoldState?

    struct TimedHoldState {
        var exerciseID: UUID
        var setID: UUID
        var targetSeconds: Int?
        var leadIn: Int
        var elapsed: Int
        var isPaused: Bool
    }

    var volumeKg: Double {
        GymCore.SessionStats.volumeKg(exercises.flatMap(\.sets).filter(\.isDone).map(\.performed))
    }

    var setsDone: Int { exercises.reduce(0) { $0 + $1.doneCount } }
    var setsTotal: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var prCount: Int { prBanner == nil ? 0 : 1 }

    /// Elapsed seconds since the session started, as of `date`.
    func elapsedSeconds(at date: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt)))
    }

    /// Index of the first exercise with an incomplete set.
    var onDeckIndex: Int? { exercises.firstIndex { !$0.isComplete } }

    /// Muscles hit so far, weighted by completed sets.
    var musclesHit: [Muscle: Double] {
        let entries = exercises.map {
            (primary: $0.exercise.primary, secondary: $0.exercise.secondary, completedCount: $0.doneCount)
        }
        return GymCore.SessionStats.musclesHit(sets: entries)
    }

    func completeSet(exerciseID: UUID, setID: UUID, effort: Effort? = nil) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].isDone = true
        if let effort { exercises[ei].sets[si].effort = effort }
        Haptics.setDone()
        startRest(seconds: exercises[ei].exercise.restSeconds, after: ei, set: si)
    }

    func uncompleteSet(exerciseID: UUID, setID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].isDone = false
    }

    func startRest(seconds: Int, after exerciseIndex: Int, set setIndex: Int) {
        restTotal = seconds
        restRemaining = seconds
        let ex = exercises[exerciseIndex]
        restNextWeightKg = nil
        restNextReps = nil
        restNextLabel = ""
        if setIndex + 1 < ex.sets.count {
            let next = ex.sets[setIndex + 1]
            restNextWeightKg = next.weightKg
            restNextReps = next.reps
        } else if exerciseIndex + 1 < exercises.count {
            restNextLabel = "Next \(exercises[exerciseIndex + 1].exercise.name)"
        } else {
            restNextLabel = "Last set done"
        }
        restExerciseName = ex.exercise.name
        restSetNumber = setIndex + 1
        restSetCount = ex.sets.count
        onRestStateChange?(restState(isEnded: false, isSkipped: false))
    }

    func tickRest() {
        guard restRemaining > 0 else { return }
        restRemaining -= 1
        if restRemaining <= 3, restRemaining > 0 { Haptics.restTick() }
        if restRemaining == 0 {
            Haptics.restEnd()
            onRestStateChange?(restState(isEnded: true, isSkipped: false))
        }
        onRestTick?(restRemaining)
    }

    /// Snapshot for the Live Activity / notification hook — see `RestState`.
    private func restState(isEnded: Bool, isSkipped: Bool) -> RestState {
        RestState(
            remaining: restRemaining, total: restTotal, workoutTitle: title, exerciseName: restExerciseName,
            setNumber: restSetNumber, setCount: restSetCount, nextWeightKg: restNextWeightKg,
            nextReps: restNextReps, fallbackNextLabel: restNextLabel, isEnded: isEnded, isSkipped: isSkipped
        )
    }

    /// Removes a set, keeping at least one set per exercise (the delete swipe action).
    func removeSet(exerciseID: UUID, setID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              exercises[ei].sets.count > 1,
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets.remove(at: si)
        Haptics.confirm()
    }

    /// Changes a set's kind (e.g. working → drop set) without touching weight or reps.
    func changeSetKind(exerciseID: UUID, setID: UUID, to kind: SetKind) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].kind = kind
        Haptics.step()
    }

    /// Generates and inserts warm-up sets before the exercise's first working set, from
    /// `GymCore.WarmupGenerator`. A no-op if warm-ups already exist or there's no working set.
    func addWarmups(exerciseID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let entry = exercises[ei]
        guard !entry.sets.contains(where: { $0.kind == .warmup }),
              let workingIndex = entry.sets.firstIndex(where: { $0.kind == .working }) else { return }
        let workingSet = entry.sets[workingIndex]
        let warmups = GymCore.WarmupGenerator.sets(
            workingWeightKg: workingSet.weightKg, style: entry.exercise.warmupLoadingStyle,
            estimatedOneRepMax: entry.exercise.bestE1RM, increment: entry.exercise.incrementKg
        )
        guard !warmups.isEmpty else { return }
        let newSets = warmups.map { SetEntry(kind: .warmup, weightKg: $0.weightKg, reps: $0.reps) }
        exercises[ei].sets.insert(contentsOf: newSets, at: workingIndex)
    }

    func adjustRest(by delta: Int) {
        restRemaining = max(0, restRemaining + delta)
        restTotal = max(restTotal, restRemaining)
        Haptics.step()
        onRestStateChange?(restState(isEnded: restRemaining == 0, isSkipped: false))
    }

    func skipRest() {
        restRemaining = 0
        Haptics.confirm()
        onRestStateChange?(restState(isEnded: true, isSkipped: true))
    }

    static func format(_ kg: Double) -> String {
        kg == kg.rounded() ? String(Int(kg)) : String(format: "%.1f", kg)
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
