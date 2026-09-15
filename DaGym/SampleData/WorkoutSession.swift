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
    /// Every mutation — a ticked set, an edited weight, an added exercise — drops the memoised
    /// totals (`volumeKg`, `setsDone`, `setsTotal`, `musclesHit`), so the header reads a cached
    /// number between edits instead of re-reducing every set on every rest-timer tick.
    var exercises: [WorkoutExerciseEntry] {
        didSet { cachedTotals = nil }
    }
    var effortScale: Effort.Scale = .rpe
    /// True for a session logged after the fact via "Log a Past Workout".
    var isBackfilled: Bool
    /// The end a backfill was started with (`date + duration`), carried here rather than on the
    /// `WorkoutModel` — a model with `endedAt` set is a *finished* workout everywhere else, so
    /// stamping it at the start made an abandoned backfill a phantom in history. `finish` reads
    /// it. Nil for a live session, and nil for a backfill re-opened after a crash (whose sets
    /// all sit at the session's own date, so it ends there).
    var backfillEndedAt: Date?
    /// The `WorkoutModel` this session is backed by, once persisted.
    var workoutID: UUID?
    /// Free-text note for the whole session, persisted to `WorkoutModel.notes`.
    var notes: String = ""
    /// Glyph for every routine feeding this session (`WorkoutExerciseEntry.routineID`), set by
    /// `WorkoutStore` alongside `exercises` when the session is built. Used to show the on-deck
    /// exercise's own routine glyph on the rest-timer Live Activity.
    var routineGlyphs: [UUID: RoutineGlyphInfo] = [:]

    /// Wall clock every timer derives from, so a test can jump time and the app survives being
    /// suspended: rest and hold state store dates, never accumulated ticks.
    @ObservationIgnored var now: () -> Date = Date.init

    /// The rounding grid warm-ups are generated on, per exercise. Warm-ups have to land on
    /// weights the lifter's own rack can build — rounding to a bare increment asks a rack with
    /// no 1.25s for 42.5 kg — but this type is UI- and store-free, so the grid is injected.
    /// Nil means "no equipment known": fall back to the exercise's increment, as before.
    @ObservationIgnored var warmupGrid: ((ExerciseInfo) -> LoadGrid)?

    /// Seeded into every new session's `warmupGrid`. Installed once at launch by `DaGymApp`,
    /// which is the only place that has both the store (for the active equipment profile) and
    /// a lifetime longer than any session. Left nil in tests and previews.
    @MainActor static var defaultWarmupGrid: ((ExerciseInfo) -> LoadGrid)?

    // Rest timer
    /// The rest timer's own observable (see `RestTimerState`): its once-a-second tick is
    /// tracked separately from `exercises`. The `rest*` names below forward to it so every
    /// existing caller — `ActiveWorkoutView`, the Live Activity, the watch — reads and writes
    /// exactly what it did before.
    let rest = RestTimerState()
    /// Every set completed at least once this session, so un-ticking a row to fix its reps and
    /// re-ticking it doesn't restart a rest that's still running.
    private var everCompletedSetIDs: Set<UUID> = []

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
        warmupGrid = Self.defaultWarmupGrid
    }

    /// Timed-hold live timer, or nil when no hold is in progress.
    var timedHold: TimedHoldState?

    /// Dates are the source of truth (`startedAt`, pauses); `leadIn`/`elapsed` are the
    /// whole-second cache `tickTimedHold()` refreshes for the card. See `WorkoutSession+TimedHold`.
    struct TimedHoldState {
        var exerciseID: UUID
        var setID: UUID
        var targetSeconds: Int?
        /// When the 3-2-1 lead-in began.
        var startedAt: Date
        /// Set while paused; the clock stops here until resume.
        var pausedAt: Date?
        /// Total time spent paused before the current pause, if any.
        var pausedInterval: TimeInterval = 0
        var leadIn: Int
        var elapsed: Int
        var isPaused: Bool { pausedAt != nil }
    }

    /// The header's numbers, reduced from `exercises` once per mutation rather than on every
    /// read (`ActiveWorkoutView` reads them on every rest tick). Ignored by observation on
    /// purpose: it is filled from inside a view's `body`, and a tracked write there would
    /// invalidate the very view that is reading it.
    @ObservationIgnored private var cachedTotals: SessionTotals?

    private struct SessionTotals {
        var volumeKg: Double
        var setsDone: Int
        var setsTotal: Int
        var musclesHit: [Muscle: Double]
    }

    private var totals: SessionTotals {
        if let cachedTotals { return cachedTotals }
        let computed = SessionTotals(
            volumeKg: exercises.reduce(0) { total, entry in
                total + GymCore.SessionStats.volumeKg(
                    entry.sets.filter(\.isDone).map { $0.performed(style: entry.exercise.loggingStyle) }
                )
            },
            setsDone: exercises.flatMap(\.sets).filter { $0.isDone && $0.kind.countsTowardStats }.count,
            setsTotal: exercises.flatMap(\.sets).filter { $0.kind.countsTowardStats }.count,
            musclesHit: GymCore.SessionStats.musclesHit(sets: exercises.map { entry in
                (
                    primary: entry.exercise.primary, secondary: entry.exercise.secondary,
                    completedCount: entry.sets.filter { $0.isDone && $0.kind.countsTowardStats }.count
                )
            })
        )
        cachedTotals = computed
        return computed
    }

    /// Σ (load lifted × reps) over completed working sets. Built per exercise because the logging
    /// style is what says whether a row's weight is load at all: an assisted row logs the
    /// machine's help, which is not lifted, so it adds nothing — the same convention History and
    /// the Finish summary use (`WorkoutModel.loadedVolumeKg`), so the number on screen mid-workout
    /// and the one in History for those same sets agree.
    var volumeKg: Double { totals.volumeKg }

    /// Working sets only — the same definition the summary card, the History row, the weekly
    /// recap and the Health write use. The header used to count warm-ups here and nowhere else,
    /// so a session read "8 / 12 sets" on screen and "6 sets" on the summary a tap later.
    var setsDone: Int { totals.setsDone }

    var setsTotal: Int { totals.setsTotal }
    var prCount: Int { prBanner == nil ? 0 : 1 }

    /// Elapsed seconds since the session started, as of `date`.
    func elapsedSeconds(at date: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt)))
    }

    /// Index of the first exercise with an incomplete set.
    var onDeckIndex: Int? { exercises.firstIndex { !$0.isComplete } }

    /// Muscles hit so far, weighted by completed *working* sets — the same sets `volumeKg` and
    /// the summary's set count are built from. Weighting by every completed row let a
    /// warm-up-heavy lift outweigh one with no warm-ups at identical working volume.
    var musclesHit: [Muscle: Double] { totals.musclesHit }

    func completeSet(exerciseID: UUID, setID: UUID, effort: Effort? = nil) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].isDone = true
        if exercises[ei].isCardio { exercises[ei].sets[si].adoptCardioTargets() }
        if let effort { exercises[ei].sets[si].effort = effort }
        let isRecheck = !everCompletedSetIDs.insert(setID).inserted
        if isRecheck, isResting { return }
        Haptics.setDone()
        startRest(seconds: restSeconds(after: ei, set: si), after: ei, set: si)
    }

    /// Marks every already-logged set as "completed at least once", for a session re-opened from
    /// the store. Without it a resumed workout treated a row the lifter had ticked days ago as
    /// brand new: un-ticking it to fix the reps and re-ticking started a full rest timer.
    func markLoggedSetsAsSeen() {
        everCompletedSetIDs = Set(exercises.flatMap(\.sets).filter(\.isDone).map(\.id))
    }

    func uncompleteSet(exerciseID: UUID, setID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].isDone = false
    }

    /// Starts (or, with `seconds == 0`, clears) the rest after `set` of `exercises[exerciseIndex]`
    /// and works out what comes next: the superset partner still owed a set this round, the next
    /// round's first set, the exercise after the group, or "Last set done" once nothing is left.
    func startRest(seconds: Int, after exerciseIndex: Int, set setIndex: Int) {
        restTotal = seconds
        restRemaining = seconds
        restEndDate = seconds > 0 ? now().addingTimeInterval(TimeInterval(seconds)) : nil
        let ex = exercises[exerciseIndex]
        restNextWeightKg = nil
        restNextReps = nil
        restNextLabel = ""
        let members = supersetMembers(containing: exerciseIndex)
        // Rounds count working sets, not rows: a warm-up belongs to no round (see
        // `WorkoutSession+Supersets.round(of:set:)`), so what follows it is simply this
        // exercise's own next row.
        let round = round(of: exerciseIndex, set: setIndex)
        if !hasUndoneSets {
            restNextLabel = "Last set done"
        } else if let round,
                  let partner = roundPartner(members: members, round: round, excluding: exerciseIndex) {
            restNextLabel = "Next \(exercises[partner].exercise.name)"
        } else if let next = nextStep(after: exerciseIndex, set: setIndex, members: members, round: round) {
            restNextWeightKg = next.weightKg
            restNextReps = next.reps
        } else if let last = members.last, last + 1 < exercises.count {
            restNextLabel = "Next \(exercises[last + 1].exercise.name)"
        } else {
            restNextLabel = "Last set done"
        }
        rest.exerciseName = ex.exercise.name
        rest.setNumber = setIndex + 1
        rest.setCount = ex.sets.count
        rest.routineGlyph = ex.routineID.flatMap { routineGlyphs[$0] }
        onRestStateChange?(restState(isEnded: seconds == 0, isSkipped: seconds == 0))
    }

    /// What comes after this set within the exercise or its superset group: the next round's
    /// first set, or — after a warm-up, which is in no round — this exercise's own next row.
    private func nextStep(after exerciseIndex: Int, set setIndex: Int, members: [Int], round: Int?)
        -> SetEntry? {
        guard let round else {
            let sets = exercises[exerciseIndex].sets
            return sets.indices.contains(setIndex + 1) ? sets[setIndex + 1] : nil
        }
        return nextRoundSet(members: members, round: round + 1)
    }

    /// Refreshes `restRemaining` from the wall clock. Safe to call as often as you like — it only
    /// reacts (haptics, hooks) when the whole-second value actually changes, so a tick after the
    /// phone was locked for two minutes lands straight on the right number.
    func tickRest() {
        guard let restEndDate, restRemaining > 0 else { return }
        let remaining = Self.secondsRemaining(until: restEndDate, now: now())
        guard remaining != restRemaining else { return }
        restRemaining = remaining
        if remaining <= 3, remaining > 0, restHaptics { Haptics.restTick() }
        if remaining == 0 {
            if restHaptics { Haptics.restEnd() }
            onRestStateChange?(restState(isEnded: true, isSkipped: false))
            self.restEndDate = nil
        }
        onRestTick?(remaining)
    }

    /// Whole seconds from `now` to `endDate`, never negative. Rounded, not truncated, so a tick
    /// that lands a few milliseconds late still reads the second it was aimed at.
    static func secondsRemaining(until endDate: Date, now: Date) -> Int {
        max(0, Int(endDate.timeIntervalSince(now).rounded()))
    }

    /// Snapshot for the Live Activity / notification hook — see `RestState`.
    private func restState(isEnded: Bool, isSkipped: Bool) -> RestState {
        rest.snapshot(workoutTitle: title, now: now(), isEnded: isEnded, isSkipped: isSkipped)
    }

    /// Removes a set, keeping at least one set per exercise (the delete swipe action). Refusing
    /// the last set buzzes `invalid` so the swipe isn't a silent no-op.
    func removeSet(exerciseID: UUID, setID: UUID) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        guard exercises[ei].sets.count > 1 else {
            Haptics.invalid()
            return
        }
        exercises[ei].sets.remove(at: si)
        Haptics.confirm()
    }

    /// Edits the effort on a set that's already logged, without re-completing it (no second
    /// "set done" haptic, no fresh rest timer).
    func setEffort(exerciseID: UUID, setID: UUID, effort: Effort) {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseID }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
        exercises[ei].sets[si].effort = effort
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
        guard !entry.isCardio, !entry.sets.contains(where: { $0.kind == .warmup }),
              let workingIndex = entry.sets.firstIndex(where: { $0.kind == .working }) else { return }
        let workingSet = entry.sets[workingIndex]
        let warmups = GymCore.WarmupGenerator.sets(
            workingWeightKg: workingSet.weightKg, style: entry.exercise.warmupLoadingStyle,
            estimatedOneRepMax: entry.exercise.bestE1RM, increment: entry.exercise.incrementKg,
            grid: warmupGrid?(entry.exercise)
        )
        guard !warmups.isEmpty else { return }
        let newSets = warmups.map { SetEntry(kind: .warmup, weightKg: $0.weightKg, reps: $0.reps) }
        exercises[ei].sets.insert(contentsOf: newSets, at: workingIndex)
    }

    /// Replaces placeholder warm-ups (planned with no weight, so they'd show 0 kg) with a ramp
    /// generated from the first working set, once that weight is known. Planned warm-ups that
    /// carry a real weight are the user's own and stay untouched.
    func fillPlaceholderWarmups() {
        for entry in exercises {
            let warmups = entry.sets.filter { $0.kind == .warmup }
            guard !warmups.isEmpty, warmups.allSatisfy({ $0.weightKg == 0 }),
                  let working = entry.sets.first(where: { $0.kind == .working }), working.weightKg > 0,
                  let ei = exercises.firstIndex(where: { $0.id == entry.id }) else { continue }
            exercises[ei].sets.removeAll { $0.kind == .warmup }
            addWarmups(exerciseID: entry.id)
        }
    }

    func adjustRest(by delta: Int) {
        guard let restEndDate else { return }
        let current = now()
        let remaining = max(0, Self.secondsRemaining(until: restEndDate, now: current) + delta)
        restRemaining = remaining
        restTotal = max(restTotal, remaining)
        self.restEndDate = remaining > 0 ? current.addingTimeInterval(TimeInterval(remaining)) : nil
        Haptics.step()
        onRestStateChange?(restState(isEnded: remaining == 0, isSkipped: false))
    }

    func skipRest() {
        restRemaining = 0
        restEndDate = nil
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
