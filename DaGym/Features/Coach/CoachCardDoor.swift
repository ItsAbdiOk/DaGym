import Foundation
import GymCore

/// Where an Insights card's claim leads: the screen that shows the evidence behind it. A
/// stalled lift opens that exercise; a coverage gap or recovery debt the muscle map; a PR the
/// records; adherence and drift the consistency view. Pure, so the mapping is testable.
enum CoachCardDoor {
    static func destination(for card: CoachCard) -> ScreenDestination {
        if let exerciseID = exerciseID(in: card.suggestedAction) {
            return .exercise(exerciseID)
        }
        if case .restMuscle(let muscle) = card.suggestedAction {
            return .muscleDetail(muscle)
        }
        switch card.rule {
        case .stalledLift, .e1rmDowntrend, .strugglingExercise:
            return .exerciseCharts
        case .deloadOverdue:
            return .thisWeek(.trends)
        case .muscleCoverageGap:
            return .muscleMap(.balance)
        case .recoveryDebt:
            return .muscleMap(.fatigue)
        case .prMilestone:
            return .thisWeek(.records)
        case .adherenceDrop, .sessionDrift, .returnFromLayoff:
            return .thisWeek(.consistency)
        case .trainingReview:
            return .progress
        }
    }

    /// The exercise a suggested action is about, when it names one.
    static func exerciseID(in action: CoachSuggestedAction) -> UUID? {
        switch action {
        case .deloadExercise(_, let id, _): id
        case .addExercise(let id, _), .changeRepRange(let id, _, _, _), .changeProgressionRule(let id, _, _):
            id
        case .replaceExercise(let id, _, _, _): id
        case .substituteExercise, .addSession, .restMuscle, .easeBackIn, .moveRestDay, .planDeloadWeek, .none:
            nil
        }
    }
}
