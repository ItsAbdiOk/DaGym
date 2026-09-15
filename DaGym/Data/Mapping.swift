import Foundation
import GymCore

/// Conversions between SwiftData models and the UI's plain value types
/// (`DaGym/SampleData/Models.swift`).
///
/// The top of the file is pure and context-free. The `WorkoutStore` extension at the bottom is
/// the narrow band that needs the store as well — reading the previous session, dating a set,
/// dating a session's end, turning logged sets into `GymCore.StimulusEvent`s. Those are
/// conversions too, and both `WorkoutStore+Workouts.swift` and `WorkoutStore+History.swift`
/// use them; the alternative was a third file, which the project can't add without XcodeGen.
/// Anything that is real query work (best e1RM, PR counts, history lookups) still lives in the
/// relevant `WorkoutStore` extension.
extension ExerciseInfo.LoggingStyle {
    /// The raw key stored on `ExerciseModel.loggingStyle` (distinct from the
    /// case's display-text raw value).
    var rawKey: String {
        switch self {
        case .weightReps: "weightReps"
        case .bodyweightReps: "bodyweightReps"
        case .assisted: "assisted"
        case .weightedBodyweight: "weightedBodyweight"
        case .timedHold: "timedHold"
        case .cardio: "cardio"
        }
    }
}

extension ExerciseInfo {
    init(model: ExerciseModel) {
        self.init(
            id: model.id, name: model.name, primary: model.primary, secondary: model.secondary,
            equipment: model.equipment, incrementKg: model.incrementKg, restSeconds: model.restSeconds,
            bar: model.bar, isFavorite: model.isFavorite, isCustom: model.isCustom,
            isPerSide: model.isPerSide, instructions: model.instructions, loggingStyle: model.style,
            dataSource: model.dataSource, sourceURL: model.sourceURL, licence: model.licence,
            authors: model.authors, seedID: model.seedID, machine: model.machine
        )
    }
}

extension SetEntry {
    /// A persisted set back as a live row.
    ///
    /// `SetLogModel` has one duration field, and what it holds depends on whether the row was
    /// ticked: a completed timed hold stores the hold that was actually done, an untouched one
    /// stores the target the session was prescribed (see `WorkoutStore.prescribedSet`). Reading
    /// it as `durationSeconds` either way meant a resumed timed hold showed its 45-second target
    /// as 45 seconds *held* — a plank logged without being done — and lost the target the timer
    /// counts down to.
    init(model: SetLogModel) {
        self.init(
            id: model.id, kind: model.setKind, weightKg: model.weightKg, reps: model.reps,
            effort: model.rpe.map { Effort(rpe: $0) }, isDone: model.isCompleted,
            durationSeconds: model.isCompleted ? model.durationSeconds : nil,
            targetSeconds: model.isCompleted ? nil : model.durationSeconds,
            prescriptionReason: model.prescriptionReason, assistanceKg: model.assistanceKg,
            // `distanceMeters` has the same two meanings as `durationSeconds` — covered, or asked for.
            distanceMeters: model.isCompleted ? model.distanceMeters : nil,
            targetDistanceMeters: model.isCompleted ? nil : model.distanceMeters,
            inclinePercent: model.inclinePercent
        )
    }
}

extension SetLogModel {
    /// Copies the mutable fields of a `SetEntry` onto this log, keeping the
    /// SwiftData identity. Used by `WorkoutStore.sync(session:)`.
    func apply(_ entry: SetEntry, order: Int) {
        self.order = order
        kind = entry.kind.rawValue
        weightKg = entry.weightKg
        reps = entry.reps
        // One stored field for two meanings: what was held (once the row is ticked) or what was
        // asked for (until then). `SetEntry.init(model:)` reads it back the same way. Without
        // persisting the target here, resuming a timed hold lost the number the timer counts to.
        durationSeconds = entry.durationSeconds ?? (entry.isDone ? nil : entry.targetSeconds)
        distanceMeters = entry.distanceMeters ?? (entry.isDone ? nil : entry.targetDistanceMeters)
        inclinePercent = entry.inclinePercent
        rpe = entry.effort?.rpe
        isCompleted = entry.isDone
        assistanceKg = entry.assistanceKg
        if !entry.prescriptionReason.isEmpty { prescriptionReason = entry.prescriptionReason }
    }
}

extension WorkoutExerciseEntry {
    /// `whyTitle` comes back from the per-set `prescriptionReason` the store already persists —
    /// the card's "+2.5 kg" / "Planned deload" headline is the same string. The engine's longer
    /// `whyBody` isn't stored anywhere, so a resumed session shows the headline without the
    /// explainer rather than nothing at all.
    init(model: WorkoutExerciseModel, exercise: ExerciseInfo) {
        let sets = (model.sets ?? [])
            .sorted { $0.order < $1.order }
            .map { SetEntry(model: $0) }
        self.init(
            id: model.id, exercise: exercise, sets: sets, supersetGroup: model.supersetGroup,
            note: model.note.isEmpty ? nil : model.note,
            whyTitle: sets.first { !$0.prescriptionReason.isEmpty }?.prescriptionReason,
            wasSubstitution: model.wasSubstitution,
            wasPlannedDeload: model.wasPlannedDeload, routineID: model.routineID
        )
    }
}

extension RoutineInfo {
    init(model: RoutineModel, exercises: [ExerciseInfo], setCount: Int, exerciseSetCounts: [Int] = []) {
        self.init(
            id: model.id, name: model.name, exercises: exercises, setCount: setCount,
            estimatedMinutes: max(20, setCount * 3),
            progressionRule: RoutineInfo.progressionLabel(model),
            progressionDetail: RoutineInfo.progressionDetailText(model),
            exerciseSetCounts: exerciseSetCounts, symbolName: model.symbolName, tint: model.tint
        )
    }

    private static func progressionLabel(_ model: RoutineModel) -> String {
        if let rule = model.progressionRuleValue { return rule.displayName }
        switch model.progressionRule {
        case "linear": return "Linear progression"
        default: return "Double progression · \(model.repRangeLow)–\(model.repRangeHigh) reps"
        }
    }

    private static func progressionDetailText(_ model: RoutineModel) -> String {
        if let rule = model.progressionRuleValue { return rule.explanation() }
        switch model.progressionRule {
        case "linear": return "Hit every rep and the weight goes up next time."
        default: return "Hit the top of the rep range on every set and the weight goes up one increment."
        }
    }
}

// MARK: - Progression rule / stall-state JSON coding (plan.md §6.5)

/// Opaque JSON coding for `GymCore.ProgressionRule`, stored on
/// `RoutineModel.progressionRuleJSON`/`RoutineExerciseModel.progressionRuleJSON`.
extension ProgressionRule {
    /// The rule editor's job (A8): reject a non-positive increment rather than persist a rule
    /// that can never increase (the engine holds forever with "no increment set"). Clamps up to
    /// the smallest increment the picker's own stepper allows.
    var incrementRejectingNonPositive: ProgressionRule {
        let floor = 0.5
        switch self {
        case .linear(let incrementKg):
            return .linear(incrementKg: max(incrementKg, floor))
        case .doubleProgression(let low, let high, let incrementKg):
            return .doubleProgression(low: low, high: high, incrementKg: max(incrementKg, floor))
        case .linearAMRAP(let incrementKg):
            return .linearAMRAP(incrementKg: max(incrementKg, floor))
        case .assisted(let stepKg):
            return .assisted(stepKg: max(stepKg, floor))
        case .rpeBased, .percentOfTrainingMax, .bodyweight, .timed:
            return self
        }
    }
}

enum ProgressionRuleCoding {
    static func encode(_ rule: ProgressionRule) -> String {
        guard let data = try? JSONEncoder().encode(rule) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ json: String?) -> ProgressionRule? {
        guard let json, let data = json.data(using: .utf8), !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(ProgressionRule.self, from: data)
    }
}

/// A `Codable` mirror of `GymCore.StallState` (which isn't itself `Codable`), stored as JSON on
/// `RoutineExerciseModel.stallJSON`.
struct StallStateDTO: Codable {
    var consecutiveMisses: Int = 0
    var lastWeightKg: Double?
    /// Double progression's "no improvement" tracker (`StallState.lastWeakestReps`).
    var lastWeakestReps: Int?
    /// Double progression's best weakest-set reps seen at `lastWeightKg`
    /// (`StallState.bestWeakestReps`).
    var bestWeakestReps: Int?
    /// Timed rule's "what was actually asked" judging target (`StallState.lastTargetSeconds`)
    /// and the plan target it was set against.
    var lastTargetSeconds: Int?
    var lastPlanTargetSeconds: Int?
    /// Reps rules' "what was actually asked" judging target (`StallState.lastTargetReps`) and
    /// the plan target it was set against.
    var lastTargetReps: Int?
    var lastPlanTargetReps: Int?
    /// Bodyweight rule's set-ladder memory (`StallState.lastTargetSets`) and the plan's own
    /// working-set count it was set against.
    var lastTargetSets: Int?
    var lastPlanTargetSets: Int?
    /// The plan's working target weight at the last judgement (`StallState.lastPlanTargetWeightKg`)
    /// — what `WorkoutStore.planOverridesPrescription` compares the plan's current target against
    /// to tell a real target edit from an unrelated routine save.
    var lastPlanTargetWeightKg: Double?
    /// Percent/TM rule's once-per-cycle bump gate (`StallState.trainingMaxCycle`).
    var trainingMaxCycle: Int?

    init(
        consecutiveMisses: Int = 0, lastWeightKg: Double? = nil, lastWeakestReps: Int? = nil,
        bestWeakestReps: Int? = nil, lastTargetSeconds: Int? = nil, lastPlanTargetSeconds: Int? = nil,
        lastTargetReps: Int? = nil, lastPlanTargetReps: Int? = nil, lastTargetSets: Int? = nil,
        lastPlanTargetSets: Int? = nil, lastPlanTargetWeightKg: Double? = nil,
        trainingMaxCycle: Int? = nil
    ) {
        self.consecutiveMisses = consecutiveMisses
        self.lastWeightKg = lastWeightKg
        self.lastWeakestReps = lastWeakestReps
        self.bestWeakestReps = bestWeakestReps
        self.lastTargetSeconds = lastTargetSeconds
        self.lastPlanTargetSeconds = lastPlanTargetSeconds
        self.lastTargetReps = lastTargetReps
        self.lastPlanTargetReps = lastPlanTargetReps
        self.lastTargetSets = lastTargetSets
        self.lastPlanTargetSets = lastPlanTargetSets
        self.lastPlanTargetWeightKg = lastPlanTargetWeightKg
        self.trainingMaxCycle = trainingMaxCycle
    }

    init(_ state: StallState) {
        consecutiveMisses = state.consecutiveMisses
        lastWeightKg = state.lastWeightKg
        lastWeakestReps = state.lastWeakestReps
        bestWeakestReps = state.bestWeakestReps
        lastTargetSeconds = state.lastTargetSeconds
        lastPlanTargetSeconds = state.lastPlanTargetSeconds
        lastTargetReps = state.lastTargetReps
        lastPlanTargetReps = state.lastPlanTargetReps
        lastTargetSets = state.lastTargetSets
        lastPlanTargetSets = state.lastPlanTargetSets
        lastPlanTargetWeightKg = state.lastPlanTargetWeightKg
        trainingMaxCycle = state.trainingMaxCycle
    }

    var stallState: StallState {
        StallState(
            consecutiveMisses: consecutiveMisses, lastWeightKg: lastWeightKg,
            lastWeakestReps: lastWeakestReps, bestWeakestReps: bestWeakestReps,
            lastTargetSeconds: lastTargetSeconds, lastPlanTargetSeconds: lastPlanTargetSeconds,
            lastTargetReps: lastTargetReps, lastPlanTargetReps: lastPlanTargetReps,
            lastTargetSets: lastTargetSets, lastPlanTargetSets: lastPlanTargetSets,
            lastPlanTargetWeightKg: lastPlanTargetWeightKg,
            trainingMaxCycle: trainingMaxCycle
        )
    }
}

extension RoutineModel {
    /// The routine-level rule, decoded from `progressionRuleJSON`. Nil for routines saved before
    /// this existed — callers fall back to `progressionRule`/`repRangeLow`/`repRangeHigh`.
    var progressionRuleValue: ProgressionRule? {
        get { ProgressionRuleCoding.decode(progressionRuleJSON) }
        set { progressionRuleJSON = newValue.map(ProgressionRuleCoding.encode) ?? "" }
    }
}

extension RoutineExerciseModel {
    /// Per-exercise override; nil defers to the routine's rule.
    var overrideRuleValue: ProgressionRule? {
        get { ProgressionRuleCoding.decode(progressionRuleJSON) }
        set { progressionRuleJSON = newValue.map(ProgressionRuleCoding.encode) }
    }

    var stallStateValue: StallState {
        get {
            guard let data = stallJSON.data(using: .utf8),
                  let dto = try? JSONDecoder().decode(StallStateDTO.self, from: data) else {
                return StallState()
            }
            return dto.stallState
        }
        set {
            let dto = StallStateDTO(newValue)
            guard let data = try? JSONEncoder().encode(dto) else { return }
            stallJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}

extension WorkoutModel {
    /// Σ (load lifted × reps) over completed working sets — **the** total for a persisted
    /// workout. An assisted row contributes 0, because its logged weight is the machine's help;
    /// see `ExerciseInfo.LoggingStyle.loadedWeightKg(logged:)` for why that is the convention.
    ///
    /// Every persisted-side total reads this one property — the History row, the History
    /// header's lifetime tonnage (and so the "Lifetime Tonnage" milestone), the weekly recap
    /// and the Apple Health write — so they cannot quote different numbers for the same sets.
    /// The live session's `WorkoutSession.volumeKg` is the same sum over the same convention.
    var loadedVolumeKg: Double {
        (exercises ?? []).reduce(0.0) { total, exerciseModel in
            let style = exerciseModel.exercise?.style ?? .weightReps
            return total + (exerciseModel.sets ?? [])
                .filter { $0.isCompleted && $0.setKind.countsTowardStats }
                .reduce(0.0) { $0 + style.loadedWeightKg(logged: $1.weightKg) * Double($1.reps) }
        }
    }

    /// Completed working sets — the count History, the recap and the Health write show. Warm-ups
    /// are excluded for the same reason everywhere: one definition of "sets".
    var loadedSetsDone: Int {
        (exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }.count
    }

    /// Whether `finish` (or the backfill pass) has stamped `volumeKg`/`setsDone`. An unstamped
    /// row reads as all zeros, which is also what a genuinely empty workout stamps — so a zero
    /// row is recomputed from its sets, which for an empty workout costs nothing.
    var hasStampedTotals: Bool { volumeKg > 0 || setsDone > 0 }

    /// Writes the persisted totals from the rows. Called by `finish`, `restoreWorkout` and the
    /// one-shot backfill; anything else that inserts a finished workout (backup import, sample
    /// data) has to call it too or the History header undercounts.
    func stampTotals() {
        volumeKg = loadedVolumeKg
        setsDone = loadedSetsDone
    }
}

extension WorkoutRecord {
    init(model: WorkoutModel, prCount: Int = 0) {
        let minutes: Int
        if let endedAt = model.endedAt {
            minutes = max(0, Int(endedAt.timeIntervalSince(model.startedAt) / 60))
        } else {
            minutes = 0
        }
        // The stamped columns when `finish` wrote them, so a History row never faults its sets;
        // otherwise the same numbers from the rows (a workout finished before the columns existed).
        let stamped = model.hasStampedTotals
        self.init(
            id: model.id, title: model.title, date: model.startedAt, durationMinutes: minutes,
            volumeKg: stamped ? model.volumeKg : model.loadedVolumeKg,
            sets: stamped ? model.setsDone : model.loadedSetsDone, prCount: prCount
        )
    }
}

extension WorkoutSession {
    /// Re-opens a persisted, unfinished workout as a live session — the inverse of
    /// `WorkoutStore.sync(session:)`. `exerciseInfo` resolves each `ExerciseModel`; the plain
    /// mapping is the default, `WorkoutStore.resumeSession(for:)` passes the store's richer
    /// `exerciseInfo(for:)`.
    convenience init(
        model: WorkoutModel, exerciseInfo: (ExerciseModel) -> ExerciseInfo = ExerciseInfo.init(model:)
    ) {
        let entries = (model.exercises ?? []).sorted { $0.order < $1.order }.map { exerciseModel in
            let info = exerciseModel.exercise.map(exerciseInfo)
                ?? ExerciseInfo(name: "Deleted exercise", primary: [], equipment: "other")
            return WorkoutExerciseEntry(model: exerciseModel, exercise: info)
        }
        self.init(
            title: model.title, subtitle: model.routineName,
            startedAt: model.startedAt, exercises: entries, isBackfilled: model.isBackfilled
        )
        workoutID = model.id
        notes = model.notes
    }
}

// MARK: - Reading the previous session

/// What the *last* session said about an exercise, and where a logged set sits in time.
///
/// These read the store, unlike the conversions above, but they are the same kind of thing: the
/// narrow bridge from the persisted workout graph to the values a live session is built out of
/// (`GymCore.PreviousSet`, a row's ghost, a set's `completedAt`). They live here rather than in
/// `WorkoutStore+Workouts.swift` because both that file and `WorkoutStore+History.swift` use
/// them, and neither had room left under the file-length cap.
extension WorkoutStore {
    /// Re-derives each set's "ghost" — the previous session's numbers shown under the row — for
    /// an entry rebuilt from the store. `sync` persists what was logged, never the ghost, so a
    /// resumed session came back with every row's previous-session hint blank. Matched by
    /// position *within each set kind*, the same rule `GymCore.AutoFill` matches by.
    func withGhosts(_ entry: WorkoutExerciseEntry, facts: SessionFacts) -> WorkoutExerciseEntry {
        var entry = entry
        let (previous, _) = previousSets(
            exerciseID: entry.exercise.id, finishedWorkouts: facts.finishedWorkouts
        )
        guard !previous.isEmpty else { return entry }
        var positions: [SetKind: Int] = [:]
        for index in entry.sets.indices {
            let kind = entry.sets[index].kind
            let position = positions[kind, default: 0]
            positions[kind] = position + 1
            let matches = previous.filter { $0.kind == kind }
            guard matches.indices.contains(position) else { continue }
            entry.sets[index].previousWeightKg = matches[position].weightKg
            entry.sets[index].previousReps = matches[position].reps
        }
        return entry
    }

    /// The most recent finished workout's logged, *completed* sets for this exercise (A6: an
    /// uncompleted "0 × 0" row is not a previous), in position order, plus that session's date
    /// for `AutoFill`'s "is the plan newer than this?" check. A session with nothing completed,
    /// a planned deload, or one logged under an excluded routine slot is skipped — the next
    /// older one is the previous.
    func previousSets(
        exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil
    ) -> (sets: [PreviousSet], date: Date?) {
        guard let previous = previousLoggedExercise(
            exerciseID: exerciseID, finishedWorkouts: finishedWorkouts
        ) else { return ([], nil) }
        let sets = (previous.exercise.sets ?? []).filter(\.isCompleted).sorted { $0.order < $1.order }
        return (
            sets.map { setModel in
                PreviousSet(
                    kind: setModel.setKind, weightKg: setModel.weightKg, reps: setModel.reps,
                    durationSeconds: setModel.durationSeconds
                )
            },
            previous.workout.startedAt
        )
    }

    /// Completed working-set count from the previous counting session (see `previousSets`);
    /// nil when the exercise was never logged. Drop, failure and rest-pause rows are extra work
    /// hung off a set that already happened, not sets of their own — counting them re-created a
    /// three-drop finisher as three more straight sets the next time the exercise was added.
    func previousWorkingSetCount(exerciseID: UUID, finishedWorkouts: [WorkoutModel]?) -> Int? {
        let previous = previousLoggedExercise(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts)
        guard let previous else { return nil }
        return (previous.exercise.sets ?? [])
            .filter { $0.isCompleted && $0.setKind.countsTowardProgression }.count
    }

    func previousLoggedExercise(
        exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil
    ) -> (exercise: WorkoutExerciseModel, workout: WorkoutModel)? {
        for workout in finishedWorkouts ?? finishedWorkoutModelsNewestFirst() {
            let candidates = (workout.exercises ?? []).filter {
                $0.exercise?.id == exerciseID && !$0.wasPlannedDeload && !$0.excludedFromProgression
                    && ($0.sets ?? []).contains(where: \.isCompleted)
            }
            if let match = candidates.min(by: { $0.order < $1.order }) { return (match, workout) }
        }
        return nil
    }

    /// A set's `completedAt`, clamped into its workout's own window.
    ///
    /// Recovery reads `completedAt ?? workout.startedAt` and decays from it, so a session logged
    /// for last Tuesday whose sets were stamped "now" read as fresh fatigue today — while the
    /// window that gathers those sets filters on `startedAt`, so a 20-day-old backfill was
    /// dropped wholesale and a 5-day-old one counted at full strength. The requirement is simply
    /// that `completedAt` lands inside `[startedAt, endedAt]`; an unfinished backfill has no end
    /// yet, so its sets sit at its start date until `finish` stamps one after it.
    static func completionDate(_ date: Date, in workout: WorkoutModel?) -> Date {
        guard let workout else { return date }
        guard let endedAt = workout.endedAt else {
            // A live session's "now" is inside its window by construction; a backfill's is not.
            return workout.isBackfilled ? workout.startedAt : max(workout.startedAt, date)
        }
        return min(max(date, workout.startedAt), max(workout.startedAt, endedAt))
    }

    /// When a session ends.
    ///
    /// A backfill ends where it was told to (`date + duration`, carried on the session since the
    /// `WorkoutModel` can't hold it without reading as finished). A live session ends now —
    /// unless "now" is implausible, which is what forgetting to tap Finish looks like: the
    /// session is re-opened next morning and stamped a 14-hour workout that inflates the coach's
    /// duration average for weeks and writes a 14-hour strength session to Health. Past the
    /// point where a duration stops carrying any signal
    /// (`TrainingConstants.coachDriftMaxSessionSeconds`, which is the threshold the coach
    /// already ignores a session at), it ends one rest after the last set that was logged.
    static func endDate(for workout: WorkoutModel, session: WorkoutSession, now: Date) -> Date {
        let lastSetAt = (workout.exercises ?? []).flatMap { $0.sets ?? [] }.compactMap(\.completedAt).max()
        if workout.isBackfilled {
            return max(workout.startedAt, session.backfillEndedAt ?? lastSetAt ?? workout.startedAt)
        }
        let cap = workout.startedAt
            .addingTimeInterval(TimeInterval(TrainingConstants.coachDriftMaxSessionSeconds))
        guard now > cap else { return max(workout.startedAt, now) }
        let tail = lastSetAt.map { $0.addingTimeInterval(forgottenFinishTailSeconds) } ?? cap
        return max(workout.startedAt, min(cap, tail))
    }

    /// How long after the last logged set a workout someone forgot to finish is taken to have
    /// ended: one typical rest, so the last set counts as done rather than mid-flight.
    private static let forgottenFinishTailSeconds: TimeInterval = 3 * 60

    func recoveryEvents(in workout: WorkoutModel) -> [StimulusEvent] {
        (workout.exercises ?? []).flatMap { exerciseModel -> [StimulusEvent] in
            guard let exercise = exerciseModel.exercise else { return [] }
            let fallbackDate = workout.startedAt
            return (exerciseModel.sets ?? [])
                .filter { $0.isCompleted && $0.setKind.countsTowardStats }
                .flatMap { stimulusEvents(for: $0, exercise: exercise, fallbackDate: fallbackDate) }
        }
    }

    /// One completed set's stimulus, attributed by `GymCore.StimulusAttribution` — the single
    /// place the "how much of a set is this, and how hard was it" conventions live, so fatigue,
    /// the body map and the volume charts cannot drift apart. This used to hard-code `0.5` for a
    /// secondary mover (against `Recovery.secondaryShare`'s 0.45), count a drop set as a whole
    /// extra set, and rate an unrated set taken to failure as if nobody knew how hard it was.
    private func stimulusEvents(
        for setLog: SetLogModel, exercise: ExerciseModel, fallbackDate: Date
    ) -> [StimulusEvent] {
        let date = setLog.completedAt ?? fallbackDate
        let kind = setLog.setKind
        let effort = StimulusAttribution.effort(kind: kind, rpe: setLog.rpe)
        let primary = exercise.primary.map { muscle in
            StimulusEvent(
                muscle: muscle, share: StimulusAttribution.share(kind: kind, isPrimary: true),
                effort: effort, date: date
            )
        }
        let secondary = exercise.secondary.map { muscle in
            StimulusEvent(
                muscle: muscle, share: StimulusAttribution.share(kind: kind, isPrimary: false),
                effort: effort, date: date
            )
        }
        return primary + secondary
    }
}
