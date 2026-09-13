import Foundation

/// One completed set as logged by the user, ready to be checked against PRs.
public struct PerformedSet: Hashable, Sendable {
    public var kind: SetKind
    public var weightKg: Double
    public var reps: Int
    public var durationSeconds: Int?
    public var assistanceKg: Double?
    public var bodyweightKg: Double?
    public var date: Date

    public init(
        kind: SetKind,
        weightKg: Double,
        reps: Int,
        durationSeconds: Int? = nil,
        assistanceKg: Double? = nil,
        bodyweightKg: Double? = nil,
        date: Date
    ) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.assistanceKg = assistanceKg
        self.bodyweightKg = bodyweightKg
        self.date = date
    }
}

/// The kind of personal record a set can earn.
public enum PRKind: String, CaseIterable, Codable, Sendable {
    case e1rm, maxWeight, maxRepsAtWeight, volume, longestHold, leastAssistance
}

/// A single earned personal record.
public struct PersonalRecord: Hashable, Sendable {
    public var kind: PRKind
    public var value: Double
    public var weightKg: Double
    public var reps: Int
    public var date: Date

    public init(kind: PRKind, value: Double, weightKg: Double, reps: Int, date: Date) {
        self.kind = kind
        self.value = value
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
    }
}

/// Evaluates completed sets against a lifter's existing records to find new PRs.
public enum PersonalRecords {
    /// Returns the new records earned by `newSets`, empty when none were beaten.
    /// Warm-ups never count. A backfilled workout dated before `latestWorkoutDate`
    /// earns nothing, since it cannot claim a PR against a later session.
    public static func evaluate(
        newSets: [PerformedSet],
        existing: [PersonalRecord],
        workoutDate: Date,
        isBackfilled: Bool,
        latestWorkoutDate: Date?
    ) -> [PersonalRecord] {
        if isBackfilled, let latest = latestWorkoutDate, workoutDate < latest {
            return []
        }
        let sets = newSets.filter { $0.kind.countsTowardStats }
        guard !sets.isEmpty else { return [] }

        var records: [PersonalRecord] = []
        records += bestSimple(.e1rm, sets: sets, date: workoutDate, existing: existing, value: e1rmValue)
        records += bestSimple(.maxWeight, sets: sets, date: workoutDate, existing: existing) { $0.weightKg }
        records += bestSimple(.volume, sets: sets, date: workoutDate, existing: existing) {
            $0.weightKg * Double($0.reps)
        }
        records += bestSimple(.longestHold, sets: sets, date: workoutDate, existing: existing) {
            $0.durationSeconds.map(Double.init)
        }
        records += leastAssistanceRecord(sets: sets, date: workoutDate, existing: existing)
        records += maxRepsAtWeightRecords(sets: sets, date: workoutDate, existing: existing)
        return records
    }

    /// Human-readable line for a record, as shown on the PR banner and history.
    public static func formatLine(_ pr: PersonalRecord) -> String {
        switch pr.kind {
        case .e1rm:
            return "\(WeightFormat.kg(pr.weightKg)) × \(pr.reps) (e1RM \(WeightFormat.kg(pr.value)))"
        case .maxWeight:
            return "Heaviest \(WeightFormat.kg(pr.value)) kg"
        case .maxRepsAtWeight:
            return "\(pr.reps) reps at \(WeightFormat.kg(pr.weightKg)) kg"
        case .volume:
            return "Volume \(WeightFormat.kg(pr.value)) kg"
        case .longestHold:
            return "Hold \(clock(Int(pr.value)))"
        case .leastAssistance:
            return "Assistance down to \(WeightFormat.kg(pr.value)) kg"
        }
    }

    /// The e1RM value for a set, using the effective weight for assisted and
    /// weighted-bodyweight styles when a bodyweight is supplied.
    private static func e1rmValue(_ set: PerformedSet) -> Double? {
        let effectiveWeight: Double
        if let bodyweight = set.bodyweightKg {
            if let assistance = set.assistanceKg {
                effectiveWeight = bodyweight - assistance
            } else {
                effectiveWeight = bodyweight + set.weightKg
            }
        } else {
            effectiveWeight = set.weightKg
        }
        return OneRepMax.estimate(weight: effectiveWeight, reps: set.reps)
    }

    /// Finds the best set for a kind where "bigger value wins", returning at
    /// most one new record when it beats the existing best (ties don't count).
    private static func bestSimple(
        _ kind: PRKind,
        sets: [PerformedSet],
        date: Date,
        existing: [PersonalRecord],
        value: (PerformedSet) -> Double?
    ) -> [PersonalRecord] {
        let best = sets.compactMap { set in value(set).map { (set: set, value: $0) } }
            .max { $0.value < $1.value }
        guard let best else { return [] }
        let currentBest = existing.first { $0.kind == kind }?.value ?? -.infinity
        guard best.value > currentBest else { return [] }
        return [
            PersonalRecord(
                kind: kind, value: best.value, weightKg: best.set.weightKg, reps: best.set.reps, date: date
            )
        ]
    }

    /// Least assistance is better: a smaller assistanceKg beats the existing record.
    private static func leastAssistanceRecord(
        sets: [PerformedSet], date: Date, existing: [PersonalRecord]
    ) -> [PersonalRecord] {
        let best = sets.compactMap { set in set.assistanceKg.map { (set: set, value: $0) } }
            .min { $0.value < $1.value }
        guard let best else { return [] }
        guard let currentBest = existing.first(where: { $0.kind == .leastAssistance })?.value else {
            return [
                PersonalRecord(
                    kind: .leastAssistance, value: best.value, weightKg: best.set.weightKg,
                    reps: best.set.reps, date: date
                )
            ]
        }
        guard best.value < currentBest else { return [] }
        return [
            PersonalRecord(
                kind: .leastAssistance, value: best.value, weightKg: best.set.weightKg,
                reps: best.set.reps, date: date
            )
        ]
    }

    /// Per weight, more reps than the existing record at that same weight.
    private static func maxRepsAtWeightRecords(
        sets: [PerformedSet], date: Date, existing: [PersonalRecord]
    ) -> [PersonalRecord] {
        var bestRepsByWeight: [Double: Int] = [:]
        for set in sets where set.reps >= 1 {
            let current = bestRepsByWeight[set.weightKg] ?? 0
            if set.reps > current {
                bestRepsByWeight[set.weightKg] = set.reps
            }
        }
        var records: [PersonalRecord] = []
        for (weight, reps) in bestRepsByWeight.sorted(by: { $0.key < $1.key }) {
            let currentBest = existing.first { $0.kind == .maxRepsAtWeight && $0.weightKg == weight }?.reps
            if let currentBest, reps <= currentBest { continue }
            records.append(
                PersonalRecord(
                    kind: .maxRepsAtWeight, value: Double(reps), weightKg: weight, reps: reps, date: date
                )
            )
        }
        return records
    }

    private static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
