import Foundation

/// One model-ranked substitute: which of the rule engine's candidates, and a one-line why.
public struct RankedSubstitute: Hashable, Sendable, Identifiable {
    public var candidateID: UUID
    public var why: String
    public var id: UUID { candidateID }

    public init(candidateID: UUID, why: String) {
        self.candidateID = candidateID
        self.why = why
    }
}

/// The gate between the model's reordering and `SwapExerciseSheet`. The model only ever sees
/// `Substitutions.candidates`' output (same muscles, available equipment, fatigue-aware) and may
/// reorder it and explain each pick — it cannot add an exercise. Anything else it returns is
/// dropped: an id outside the candidate list, a duplicate, an empty why (the rule's own why is
/// kept for that row). Candidates the model left out are appended in rule order, so the sheet
/// never loses an option because the model forgot one.
public enum SubstitutionRankingValidator {
    /// Nil when nothing the model returned was usable — the caller then shows the rule order.
    public static func validate(
        _ ranked: [RankedSubstitute], candidates: [ScoredSubstitute]
    ) -> [RankedSubstitute]? {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var result: [RankedSubstitute] = []
        for pick in ranked {
            guard let candidate = byID[pick.candidateID], !seen.contains(pick.candidateID) else { continue }
            seen.insert(pick.candidateID)
            let why = pick.why.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(RankedSubstitute(
                candidateID: pick.candidateID, why: why.isEmpty ? candidate.reason : why
            ))
        }
        guard !result.isEmpty else { return nil }
        for candidate in candidates where !seen.contains(candidate.id) {
            result.append(RankedSubstitute(candidateID: candidate.id, why: candidate.reason))
        }
        return result
    }

    /// The rule order, unchanged, as ranked substitutes — the fallback when no model is available.
    public static func ruleOrder(_ candidates: [ScoredSubstitute]) -> [RankedSubstitute] {
        candidates.map { RankedSubstitute(candidateID: $0.id, why: $0.reason) }
    }
}

/// Reads a free-text swap reason ("the cable machine's taken", "my left shoulder is sore",
/// "only have dumbbells today") back into the closed `SwapReason` set the rule engine scores
/// with. Keyword matching, deliberately dumb: it feeds the *rule* path, and the model path gets
/// the raw text as well. Nil when nothing matched, so the caller keeps the chip the lifter chose.
public enum SwapReasonParser {
    public static func parse(_ text: String) -> SwapReason? {
        let lowered = text.lowercased()
        guard !lowered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let muscle = painMuscle(in: lowered) {
            return muscle == .delts ? .shoulderHurts : .painArea(muscle)
        }
        if lowered.contains("machine") || lowered.contains("taken") || lowered.contains("busy")
            || lowered.contains("occupied") || lowered.contains("queue") {
            return .machineTaken
        }
        if lowered.contains("barbell") || lowered.contains("no bar") || lowered.contains("rack") {
            return .noBarbell
        }
        if lowered.contains("time") || lowered.contains("quick") || lowered.contains("hurry")
            || lowered.contains("rush") {
            return .shortOnTime
        }
        if lowered.contains("struggl") || lowered.contains("stuck") || lowered.contains("can't")
            || lowered.contains("failing") {
            return .strugglingWithExercise
        }
        return nil
    }

    /// The first body part named next to a pain word. Only the muscles the swap engine can steer
    /// away from are recognised, by their everyday names.
    private static func painMuscle(in text: String) -> Muscle? {
        let painWords = ["hurt", "sore", "pain", "ache", "tweak", "pinch", "strain", "tight"]
        guard painWords.contains(where: text.contains) else { return nil }
        let names: [(String, Muscle)] = [
            ("shoulder", .delts), ("delt", .delts), ("knee", .quads), ("quad", .quads),
            ("hamstring", .hams), ("lower back", .lowerBack), ("back", .lats), ("lat", .lats),
            ("elbow", .triceps), ("tricep", .triceps), ("bicep", .biceps), ("wrist", .forearms),
            ("forearm", .forearms), ("chest", .chest), ("pec", .chest), ("glute", .glutes),
            ("hip", .glutes), ("calf", .calves), ("calves", .calves), ("neck", .traps), ("trap", .traps)
        ]
        return names.first { text.contains($0.0) }?.1
    }
}
