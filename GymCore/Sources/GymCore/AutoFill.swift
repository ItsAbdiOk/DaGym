import Foundation

/// One completed set from a previous session, used to pre-fill the next one.
public struct PreviousSet: Hashable, Sendable {
    public var kind: SetKind
    public var weightKg: Double
    public var reps: Int
    public var durationSeconds: Int?

    public init(kind: SetKind, weightKg: Double, reps: Int, durationSeconds: Int? = nil) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
    }
}

/// A pre-filled weight/reps for one planned set, with the ghost text and why.
public struct Prescription: Hashable, Sendable {
    public var weightKg: Double
    public var reps: Int
    public var durationSeconds: Int?
    public var previous: String?
    public var reason: String
    /// For `.assisted`: the assistance to set on the machine/band. `weightKg` carries the
    /// same number there for callers that predate this field — prefer this one.
    public var assistanceKg: Double?

    public init(
        weightKg: Double, reps: Int, durationSeconds: Int? = nil, previous: String?, reason: String,
        assistanceKg: Double? = nil
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.previous = previous
        self.reason = reason
        self.assistanceKg = assistanceKg
    }
}

/// Pre-fills a planned workout's sets from the previous session, matched by
/// position within each set kind.
public enum AutoFill {
    // swiftlint:disable large_tuple
    /// - Parameters:
    ///   - planned: the routine's sets in order, as (kind, target reps, target weight, target seconds).
    ///   - previous: the same exercise's sets from the most recent prior session, in order.
    ///     Callers must pass only completed sets — an uncompleted "0 × 0" row is not a previous.
    ///   - incrementKg: unused; kept so existing call sites compile.
    ///   - planUpdatedAt: when the routine's targets were last edited. A plan target edited
    ///     after `previousDate` wins over the previous session ("From your updated plan") —
    ///     otherwise the lifter's routine edit would be ignored forever.
    ///   - previousDate: when the `previous` session happened.
    public static func prescriptions(
        planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)],
        previous: [PreviousSet],
        incrementKg: Double = 0,
        planUpdatedAt: Date? = nil,
        previousDate: Date? = nil
    ) -> [Prescription] {
        var seenByKind: [SetKind: Int] = [:]
        var previousByKind: [SetKind: [PreviousSet]] = [:]
        for set in previous {
            previousByKind[set.kind, default: []].append(set)
        }
        let planIsNewer: Bool
        if let planUpdatedAt, let previousDate {
            planIsNewer = planUpdatedAt > previousDate
        } else {
            planIsNewer = false
        }

        return planned.map { plan in
            let position = seenByKind[plan.kind, default: 0]
            seenByKind[plan.kind] = position + 1
            if planIsNewer, plan.targetWeightKg != nil || plan.targetSeconds != nil {
                return Prescription(
                    weightKg: plan.targetWeightKg ?? 0, reps: plan.targetReps ?? 0,
                    durationSeconds: plan.targetSeconds, previous: nil, reason: "From your updated plan"
                )
            }
            let match = previousByKind[plan.kind]?[safe: position]
            if match == nil, let last = previousByKind[plan.kind]?.last {
                // A planned set beyond what was logged last time: repeat the last matched set
                // rather than falling back to a (usually empty) plan target. No ghost — it
                // isn't literally "what you did in this slot".
                return Prescription(
                    weightKg: last.weightKg, reps: last.reps, durationSeconds: last.durationSeconds,
                    previous: nil, reason: "Like your last set"
                )
            }
            return prescription(for: plan, matching: match)
        }
    }

    private static func prescription(
        for plan: (kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?),
        matching previous: PreviousSet?
    ) -> Prescription {
        guard let previous else {
            return Prescription(
                weightKg: plan.targetWeightKg ?? 0,
                reps: plan.targetReps ?? 0,
                durationSeconds: plan.targetSeconds,
                previous: nil,
                reason: plan.targetReps != nil || plan.targetWeightKg != nil || plan.targetSeconds != nil
                    ? "From your plan"
                    : "First time — enter a weight"
            )
        }
        let weightReps = "\(WeightFormat.kg(previous.weightKg)) × \(previous.reps)"
        let ghost = previous.durationSeconds.map(clock) ?? weightReps
        return Prescription(
            weightKg: previous.weightKg,
            reps: previous.reps,
            durationSeconds: previous.durationSeconds,
            previous: ghost,
            reason: "Same as last time"
        )
    }

    private static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
    // swiftlint:enable large_tuple
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Formats a weight in kilograms, dropping a trailing ".0".
public enum WeightFormat {
    public static func kg(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
