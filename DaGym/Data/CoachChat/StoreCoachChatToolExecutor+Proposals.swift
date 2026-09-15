import Foundation
import GymCore

/// The five `propose_*` tools. The arguments are already a `CoachChatDraft` (the proposal
/// types are the tool schemas); this validates it against the library and the lifter's
/// equipment, fills in what only the store knows (routine names, which routine holds the
/// swapped exercise) and returns the draft for the card — or throws every reason at once.
extension StoreCoachChatToolExecutor {
    struct DraftAcceptedPayload: Codable {
        var draft: String
        var summary: String
        var status: String
    }

    func propose(_ draft: CoachChatDraft) throws -> CoachChatToolResult {
        let availability = store.equipmentAvailabilityForProgram()
        let library = store.substitutionCandidates()
        var validated: CoachChatDraft
        switch draft.validate(availability: availability, library: library) {
        case .success(let accepted): validated = accepted
        case .failure(let rejection): throw CoachChatToolError.rejected(rejection.reasons)
        }
        var reasons: [String] = []
        switch validated {
        case .schedule(let proposal): validated = .schedule(checkSchedule(proposal, reasons: &reasons))
        case .swap(let proposal): validated = .swap(checkSwap(proposal, reasons: &reasons))
        case .deload(let proposal): checkDeload(proposal, reasons: &reasons)
        case .routine, .program: break
        }
        guard reasons.isEmpty else { throw CoachChatToolError.rejected(reasons) }
        let payload = DraftAcceptedPayload(
            draft: Self.kind(of: validated), summary: validated.summary,
            status: "Shown to the lifter as a card to apply or discard. Nothing is saved yet."
        )
        return .draft(validated, summaryJSON: try encodeJSON(payload))
    }

    static func kind(of draft: CoachChatDraft) -> String {
        switch draft {
        case .routine: "routine"
        case .program: "program"
        case .schedule: "schedule"
        case .deload: "deload"
        case .swap: "swap"
        }
    }

    /// Every routine id must be a live routine; names are filled for the card.
    private func checkSchedule(_ proposal: ScheduleProposal, reasons: inout [String]) -> ScheduleProposal {
        var result = proposal
        let names = Dictionary(
            store.routines().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        for (day, id) in proposal.days.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let name = names[id] else {
                reasons.append("\(day.displayName): no routine with id \(id.uuidString); use list_routines.")
                continue
            }
            result.routineNames[id] = name
        }
        return result
    }

    /// The routine must exist and must currently program the outgoing exercise.
    private func checkSwap(_ proposal: SwapProposal, reasons: inout [String]) -> SwapProposal {
        var result = proposal
        guard let routine = store.routine(id: proposal.routineID) else {
            reasons.append("No routine with id \(proposal.routineID.uuidString); use list_routines.")
            return result
        }
        result.routineName = routine.name
        if let from = proposal.fromExerciseID, !routine.exercises.contains(where: { $0.id == from }) {
            let name = proposal.fromExerciseName ?? from.uuidString
            reasons.append("'\(routine.name)' does not include '\(name)'; use get_routine.")
        }
        return result
    }

    /// A deload needs a working weight to cut from: a logged session or a planned target.
    private func checkDeload(_ proposal: DeloadProposal, reasons: inout [String]) {
        guard let id = proposal.exerciseID else { return }
        let name = proposal.exerciseName ?? id.uuidString
        guard !store.routinesUsing(exerciseID: id).isEmpty else {
            reasons.append("No routine programs '\(name)', so there is nothing to deload.")
            return
        }
        if store.coachChatWorkingWeightKg(exerciseID: id) == nil {
            reasons.append("'\(name)' has no logged weight or planned target to deload from.")
        }
    }
}
