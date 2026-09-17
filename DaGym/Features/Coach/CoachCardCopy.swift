import GymCore

/// The words on an Insights card that come from its rule and action rather than the engine:
/// the kicker's rule name, the action button's label, and the honest line under the evidence
/// on what tapping it actually does. Pure, so a test can pin every case.
enum CoachCardCopy {
    /// "Deload overdue", "Muscle coverage" — the rule as the kicker names it.
    static func kicker(for rule: CoachRule) -> String {
        kickers[rule] ?? "Insight"
    }

    private static let kickers: [CoachRule: String] = [
        .adherenceDrop: "Adherence",
        .sessionDrift: "Session drift",
        .muscleCoverageGap: "Muscle coverage",
        .stalledLift: "Stalled lift",
        .e1rmDowntrend: "Strength trend",
        .deloadOverdue: "Deload overdue",
        .strugglingExercise: "Struggling exercise",
        .recoveryDebt: "Recovery",
        .prMilestone: "PR milestone",
        .returnFromLayoff: "Back from a break",
        .trainingReview: "Training review"
    ]

    /// The action button. Actions the app carries out for real say what they do ("Deload to
    /// 60 kg", "Add Face Pull"); the ones that only record the lifter's decision say "Approve",
    /// because a button reading "Swap for Cable Row" that swapped nothing would be a lie.
    static func primaryLabel(for action: CoachSuggestedAction, formatWeight: (Double) -> String) -> String {
        switch action {
        case .deloadExercise(_, _, let toWeightKg): "Deload to \(formatWeight(toWeightKg))"
        case .addExercise(_, let exerciseName): "Add \(exerciseName)"
        case .replaceExercise(_, _, _, let withName): "Swap for \(withName)"
        case .changeRepRange(_, _, let low, let high): "Set \(low)–\(high) reps"
        case .changeProgressionRule(_, _, let rule): "Use \(rule.displayName)"
        case .moveRestDay(_, let to): "Move to \(to.displayName)"
        case .substituteExercise, .addSession, .restMuscle, .easeBackIn: "Approve"
        case .none: "Got it"
        }
    }

    /// What the action button actually does for this card — honest either way: a deload and
    /// the training-review changes are applied for real (`WorkoutStore.applyCoachDeload`,
    /// `applyReviewChange`) and undoable from the toast; everything else is recorded but left
    /// for the lifter to act on themselves.
    static func actionNote(for action: CoachSuggestedAction, formatWeight: (Double) -> String) -> String? {
        switch action {
        case .deloadExercise(let exerciseName, _, let toWeightKg):
            // Says exactly what is written, and nothing that isn't: the target weight changes,
            // the set count doesn't, and it takes effect the next time this lift comes up.
            "Sets \(exerciseName)'s target weight to \(formatWeight(toWeightKg)) in your plan, so "
                + "that's what your next session starts from. Your set count and rep targets don't "
                + "change, and you can undo it."
        case .substituteExercise(_, _, let candidateName):
            "Approve just records your decision — to make the swap, tap the set's swap button next "
                + "time you train it and pick \(candidateName)."
        case .addSession(let weekday):
            "Approve just records your decision — add \(weekday.displayName) from Schedule."
        case .restMuscle(let muscle):
            "Approve just records your decision — ease off \(muscle.displayName) yourself for a day or two."
        case .easeBackIn(let loadFraction):
            "Approve just records your decision — start your next session around "
                + "\(Int((loadFraction * 100).rounded()))% of your usual weight."
        case .addExercise, .replaceExercise, .changeRepRange, .changeProgressionRule, .moveRestDay:
            reviewActionNote(for: action)
        case .none:
            nil
        }
    }

    /// The training-review actions (`CoachReviewSection`): each one is applied for real by
    /// `WorkoutStore.applyReviewChange`, and each is undoable from the toast.
    private static func reviewActionNote(for action: CoachSuggestedAction) -> String? {
        switch action {
        case .addExercise(_, let exerciseName):
            "Adds \(exerciseName) (3 × 8) to the routine that already trains its muscles most. "
                + "You can undo it."
        case .replaceExercise(_, let exerciseName, _, let withName):
            "Swaps \(exerciseName) for \(withName) in every routine that programmes it. Progress on "
                + "\(exerciseName) is kept. You can undo it."
        case .changeRepRange(_, let exerciseName, let low, let high):
            "Sets \(exerciseName)'s working sets to \(low)–\(high) reps in your plan. You can undo it."
        case .changeProgressionRule(_, let exerciseName, let rule):
            "Puts \(exerciseName) on \(rule.displayName) progression. You can undo it."
        case .moveRestDay(let from, let to):
            "Moves \(from.displayName)'s session to \(to.displayName) in your schedule. You can undo it."
        case .deloadExercise, .substituteExercise, .addSession, .restMuscle, .easeBackIn, .none:
            nil
        }
    }
}
