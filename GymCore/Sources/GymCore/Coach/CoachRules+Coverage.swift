import Foundation

/// Muscle-coverage-gap rule: reads the sets-per-muscle map the app layer already computed via
/// `BodySeries.setsPerMuscle(workouts:window:now:calendar:)` over the rolling
/// `TrainingConstants.coachCoverageWindowDays` window — this rule only interprets that map, it
/// doesn't re-walk workouts itself.
extension CoachRules {
    /// One under-trained muscle and its set count in the rolling window.
    private struct CoverageGap {
        let muscle: Muscle
        let sets: Double
    }

    static func muscleCoverageCards(input: CoachInput, now: Date) -> [CoachCard] {
        guard !input.trackedMuscles.isEmpty else { return [] }
        let floor = TrainingConstants.coachMinSetsPerMuscleInWindow
        // Spelled out with a named type rather than a tuple chain: the inferred
        // map/filter/sorted pipeline pushed the type checker past its time limit.
        var gaps: [CoverageGap] = []
        for muscle in input.trackedMuscles {
            let sets = input.muscleSetsInWindow[muscle] ?? 0
            if sets < floor { gaps.append(CoverageGap(muscle: muscle, sets: sets)) }
        }
        gaps.sort { lhs, rhs in
            lhs.sets == rhs.sets ? lhs.muscle.rawValue < rhs.muscle.rawValue : lhs.sets < rhs.sets
        }
        guard !gaps.isEmpty else { return [] }

        let named = Array(gaps.prefix(TrainingConstants.coachCoverageMaxNamedMuscles))
        let names = named.map(\.muscle.displayName).joined(separator: ", ")
        let evidence = named.map {
            CoachEvidenceItem("\($0.muscle.displayName) sets in window", .number($0.sets))
        } + [CoachEvidenceItem("Window (days)", .count(TrainingConstants.coachCoverageWindowDays))]
        let key = named.map(\.muscle.rawValue).joined(separator: ",")
        let verb = named.count == 1 ? "hasn't" : "haven't"

        return [CoachCard(
            rule: .muscleCoverageGap, severity: .info, title: "Coverage gap: \(names)",
            body: "\(names) \(verb) seen enough sets in the last "
                + "\(TrainingConstants.coachCoverageWindowDays) days.",
            evidence: evidence, suggestedAction: .none, distinguishingKey: key, firedDate: now
        )]
    }
}
