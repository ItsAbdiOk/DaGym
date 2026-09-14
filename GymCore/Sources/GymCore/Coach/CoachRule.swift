import Foundation

/// The ten rule-based coach checks (plan.md: "a deterministic, rule-based coach"). Each has a
/// stable string id — used to persist dismissals/approvals across app launches — and a cooldown,
/// so a dismissed card doesn't come straight back once its underlying evidence changes.
public enum CoachRule: String, CaseIterable, Codable, Hashable, Sendable {
    /// Completion rate against the lifter's own schedule has dropped recently.
    case adherenceDrop = "coach.adherenceDrop"
    /// Sessions are getting shorter or sets are being skipped, vs. the lifter's own baseline.
    case sessionDrift = "coach.sessionDrift"
    /// A muscle group has fallen under its minimum sets in the rolling coverage window.
    case muscleCoverageGap = "coach.muscleCoverageGap"
    /// One lift has stopped moving at the same weight for several sessions in a row.
    case stalledLift = "coach.stalledLift"
    /// One lift's e1RM is trending down over its last several sessions.
    case e1rmDowntrend = "coach.e1rmDowntrend"
    /// `DeloadDetector` found enough evidence (stalls, e1RM regression, rising RPE, or too many
    /// hard weeks) to suggest a deload.
    case deloadOverdue = "coach.deloadOverdue"
    /// An exercise the lifter keeps missing or failing — offer a substitution.
    case strugglingExercise = "coach.strugglingExercise"
    /// Several muscles are still carrying meaningful fatigue — a rest day or easy session is due.
    case recoveryDebt = "coach.recoveryDebt"
    /// A personal record or milestone tier was earned recently and is worth calling out.
    case prMilestone = "coach.prMilestone"
    /// The lifter is returning after a long layoff — ease back in rather than picking up where
    /// they left off.
    case returnFromLayoff = "coach.returnFromLayoff"

    /// How long a dismissal or approval of this rule silences it, even if the same evidence
    /// (same fingerprint) would otherwise fire again.
    public var cooldownDays: Int {
        switch self {
        case .adherenceDrop: TrainingConstants.coachAdherenceCooldownDays
        case .sessionDrift: TrainingConstants.coachDriftCooldownDays
        case .muscleCoverageGap: TrainingConstants.coachCoverageCooldownDays
        case .stalledLift: TrainingConstants.coachStalledLiftCooldownDays
        case .e1rmDowntrend: TrainingConstants.coachE1rmDowntrendCooldownDays
        case .deloadOverdue: TrainingConstants.coachDeloadCooldownDays
        case .strugglingExercise: TrainingConstants.coachSubstitutionCooldownDays
        case .recoveryDebt: TrainingConstants.coachRecoveryDebtCooldownDays
        case .prMilestone: TrainingConstants.coachHighlightCooldownDays
        case .returnFromLayoff: TrainingConstants.coachLayoffCooldownDays
        }
    }
}
