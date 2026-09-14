import Foundation

/// One completed set as logged by the user, ready to be checked against PRs.
///
/// ## What the weight fields mean
///
/// - `weightKg` is **external load actually lifted**, and nothing else. A bodyweight-only set
///   and an assisted set both carry 0: assistance is help, not load, so it belongs in
///   `assistanceKg`. Anything that totals "weight moved" (volume, tonnage, the top-set chart,
///   the `maxWeight`/`volume` records) reads this field and is therefore always honest.
///   Callers building a `PerformedSet` from an assisted row — where the UI stores the
///   assistance dialled in as the row's weight — must move it across.
/// - `assistanceKg` is the assistance for an assisted lift, and its presence is what *makes*
///   the set assisted. Less is better (`PRKind.leastAssistance`).
/// - `bodyweightKg` is the lifter's bodyweight as of the session, supplied only for the styles
///   where it is part of the load: assisted and weighted-bodyweight. A bodyweight-only set must
///   leave it nil — otherwise the lifter's own mass turns air squats into a 113 kg e1RM.
///
/// ## Per-side loads
///
/// `weightKg` is one implement's weight for a unilateral ("per side") exercise — the number the
/// lifter typed, the number the plate calculator builds and the number the progression engine
/// increments. It is deliberately **not** doubled here or anywhere else: a 30 kg dumbbell press
/// reads "Best set 30 × 10 (300 kg)", not 600. One convention, applied everywhere, beats a
/// truer number applied in some places and not others; `ExerciseInfo.isPerSide` is the flag a
/// future display layer would use if the app ever chooses to render a bilateral total.
public struct PerformedSet: Hashable, Sendable {
    public var kind: SetKind
    /// External load lifted — see the type's note. 0 for bodyweight-only and assisted sets.
    public var weightKg: Double
    public var reps: Int
    public var durationSeconds: Int?
    /// Assistance dialled in; its presence marks the set as an assisted lift.
    public var assistanceKg: Double?
    /// Bodyweight as of the session — only for assisted and weighted-bodyweight styles.
    public var bodyweightKg: Double?
    public var date: Date
    /// Rated effort, when the lifter logged one — lets balance views single out hard sets.
    public var rpe: Double?
    /// Canonical metres covered by a cardio set; nil for everything else.
    public var distanceMeters: Double?

    public init(
        kind: SetKind,
        weightKg: Double,
        reps: Int,
        durationSeconds: Int? = nil,
        assistanceKg: Double? = nil,
        bodyweightKg: Double? = nil,
        date: Date,
        rpe: Double? = nil,
        distanceMeters: Double? = nil
    ) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.assistanceKg = assistanceKg
        self.bodyweightKg = bodyweightKg
        self.date = date
        self.rpe = rpe
        self.distanceMeters = distanceMeters
    }

    /// A "hard" set for the balance map: rated at RIR ≤ `TrainingConstants.hardSetMaxRIR`, or
    /// taken to failure / as an AMRAP regardless of rating.
    public var isHard: Bool {
        if kind == .failure || kind == .amrap { return true }
        guard let rpe else { return false }
        return Effort(rpe: rpe).rir <= TrainingConstants.hardSetMaxRIR
    }

    /// The load an e1RM should be estimated from — **the** definition, used by the PR cache and
    /// by `ExerciseSeries.e1rm` alike so the card and the chart never disagree.
    ///
    /// - assisted: bodyweight minus assistance. Nil without a bodyweight on file, because there
    ///   is no honest answer: reading the raw `weightKg` would estimate a 1RM from the *help*.
    ///   Nil (rather than 0) also when the assistance meets or exceeds bodyweight — nothing was
    ///   lifted yet.
    /// - weighted bodyweight: bodyweight plus the added load.
    /// - everything else: the load itself, which is 0 (and so ineligible) for a bodyweight-only
    ///   set. Air squats do not have a one-rep max.
    public var effectiveWeightKg: Double? {
        if let assistanceKg {
            guard let bodyweightKg else { return nil }
            let net = bodyweightKg - assistanceKg
            return net > 0 ? net : nil
        }
        if let bodyweightKg { return bodyweightKg + weightKg }
        return weightKg
    }
}

/// The kind of personal record a set can earn. Stored by raw value (`PersonalRecordModel.kind`),
/// so cases are only ever appended: `longestDistance` and `fastestPace` are the cardio pair.
public enum PRKind: String, CaseIterable, Codable, Sendable {
    case e1rm, maxWeight, maxRepsAtWeight, volume, longestHold, leastAssistance
    /// Furthest a cardio set has gone, in metres.
    case longestDistance
    /// Quickest seconds-per-km over a set of at least `PersonalRecords.paceMinimumDistanceMeters`,
    /// so a 200 m sprint can't hold the "fastest pace" over a 10 km run.
    case fastestPace
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
    /// Returns the new records earned by `newSets`, empty when none were beaten. Warm-ups never
    /// count.
    ///
    /// This is a pure "do these sets beat these bests" comparison and knows nothing about where
    /// the workout sits in history. Whether a past-dated session may be judged incrementally at
    /// all is the caller's decision, because only the caller can see the rest of the history —
    /// see `WorkoutStore.evaluatePRs`, which replays everything rather than comparing when a
    /// workout is dated before one already logged.
    public static func evaluate(
        newSets: [PerformedSet],
        existing: [PersonalRecord],
        workoutDate: Date
    ) -> [PersonalRecord] {
        let sets = newSets.filter { $0.kind.countsTowardStats }
        guard !sets.isEmpty else { return [] }

        var records: [PersonalRecord] = []
        // A bodyweight-only set has no e1RM at all: `effectiveWeightKg` is its (zero) external
        // load, which `OneRepMax` rejects. Before that, any lifter with a weigh-in on file had
        // their own mass folded in, banked a ~113 kg e1RM for 12 air squats, and
        // `bestE1RMByExerciseKey` handed them a strength milestone for it — while a lifter who
        // had never weighed in saw nothing. `minValue` keeps a degenerate zero out of the cache
        // the same way maxWeight and volume do. The record's own `weightKg` is the *effective*
        // load, so an assisted or weighted-bodyweight line reads "100 × 5 (e1RM 117)" rather
        // than quoting the 20 kg belt or the 0 kg an assisted row carries.
        records += bestSimple(
            .e1rm, sets: sets, date: workoutDate, existing: existing, minValue: 0,
            weightKg: { $0.effectiveWeightKg ?? $0.weightKg }, value: e1rmValue
        )
        // A 0 kg set (bodyweight push-ups, planks) shouldn't bank a "Heaviest 0 kg" or
        // "Best set … (0 kg)" record — those are only meaningful once real load is involved.
        records += bestSimple(
            .maxWeight, sets: sets, date: workoutDate, existing: existing, minValue: 0
        ) { $0.weightKg }
        records += bestSimple(
            .volume, sets: sets, date: workoutDate, existing: existing, minValue: 0
        ) { $0.weightKg * Double($0.reps) }
        // A row ticked without the timer ever running is a 0-second hold, not a "Hold 0:00" PR.
        // A cardio set's time is a run, not a hold — it competes for `fastestPace` instead.
        records += bestSimple(
            .longestHold, sets: sets, date: workoutDate, existing: existing, minValue: 0
        ) {
            $0.distanceMeters == nil ? $0.durationSeconds.map(Double.init) : nil
        }
        records += leastAssistanceRecord(sets: sets, date: workoutDate, existing: existing)
        records += maxRepsAtWeightRecords(sets: sets, date: workoutDate, existing: existing)
        records += bestSimple(
            .longestDistance, sets: sets, date: workoutDate, existing: existing, minValue: 0
        ) { $0.distanceMeters }
        records += fastestPaceRecord(sets: sets, date: workoutDate, existing: existing)
        return records
    }

    /// A pace only counts over at least this far: 1 km.
    public static let paceMinimumDistanceMeters = 1000.0

    /// Human-readable line for a record, as shown on the PR banner and history. `unit` controls
    /// how the weight numbers are formatted; defaults to kg for callers that haven't gone
    /// through unit-aware display yet.
    public static func formatLine(
        _ pr: PersonalRecord, unit: WeightUnit = .kg, distanceUnit: DistanceUnit = .km
    ) -> String {
        switch pr.kind {
        case .e1rm:
            return "\(unit.format(kg: pr.weightKg)) × \(pr.reps) (e1RM \(unit.format(kg: pr.value)))"
        case .maxWeight:
            return "Heaviest \(unit.format(kg: pr.value)) \(unit.symbol)"
        case .maxRepsAtWeight:
            // A rep PR at 0 kg is a bodyweight PR — "at 0 kg" would be nonsense to a lifter.
            guard pr.weightKg > 0 else { return "\(pr.reps) reps bodyweight" }
            return "\(pr.reps) reps at \(unit.format(kg: pr.weightKg)) \(unit.symbol)"
        case .volume:
            return "Best set \(unit.format(kg: pr.weightKg)) × \(pr.reps) "
                + "(\(unit.format(kg: pr.value)) \(unit.symbol))"
        case .longestHold:
            return "Hold \(clock(Int(pr.value)))"
        case .leastAssistance:
            return "Assistance down to \(unit.format(kg: pr.value)) \(unit.symbol)"
        case .longestDistance:
            return "Longest \(distanceUnit.formatWithSymbol(meters: pr.value))"
        case .fastestPace:
            // `value` is seconds per km; re-expressed per the display unit.
            let perUnit = pr.value * distanceUnit.meters / 1000
            let floor = distanceUnit.formatWithSymbol(meters: paceMinimumDistanceMeters, decimals: 1)
            let pace = CardioPace.clock(Int(perUnit.rounded()))
            return "Fastest \(pace) /\(distanceUnit.symbol) over \(floor)+"
        }
    }

    /// The e1RM value for a set: the canonical formula over `PerformedSet.effectiveWeightKg`.
    private static func e1rmValue(_ set: PerformedSet) -> Double? {
        guard let weight = set.effectiveWeightKg else { return nil }
        return OneRepMax.estimate(weight: weight, reps: set.reps)
    }

    /// Finds the best set for a kind where "bigger value wins", returning at
    /// most one new record when it beats the existing best (ties don't count).
    private static func bestSimple(
        _ kind: PRKind,
        sets: [PerformedSet],
        date: Date,
        existing: [PersonalRecord],
        minValue: Double = -.infinity,
        weightKg: (PerformedSet) -> Double = { $0.weightKg },
        value: (PerformedSet) -> Double?
    ) -> [PersonalRecord] {
        let best = sets.compactMap { set in value(set).map { (set: set, value: $0) } }
            .max { $0.value < $1.value }
        guard let best, best.value > minValue else { return [] }
        let currentBest = existing.first { $0.kind == kind }?.value ?? -.infinity
        guard best.value > currentBest else { return [] }
        return [
            PersonalRecord(
                kind: kind, value: best.value, weightKg: weightKg(best.set), reps: best.set.reps, date: date
            )
        ]
    }

    /// Fastest pace is better: fewer seconds per km, over a set that went at least
    /// `paceMinimumDistanceMeters`. Both a distance and a time are needed for a pace at all.
    private static func fastestPaceRecord(
        sets: [PerformedSet], date: Date, existing: [PersonalRecord]
    ) -> [PersonalRecord] {
        let paced = sets.compactMap { set -> (set: PerformedSet, value: Double)? in
            guard let distance = set.distanceMeters, distance >= paceMinimumDistanceMeters,
                  let seconds = set.durationSeconds,
                  let pace = CardioPace.secondsPerUnit(
                    distanceMeters: distance, durationSeconds: seconds, unit: .km
                  ) else { return nil }
            return (set, pace)
        }
        guard let best = paced.min(by: { $0.value < $1.value }) else { return [] }
        if let currentBest = existing.first(where: { $0.kind == .fastestPace })?.value,
           best.value >= currentBest {
            return []
        }
        return [
            PersonalRecord(
                kind: .fastestPace, value: best.value, weightKg: best.set.weightKg,
                reps: best.set.reps, date: date
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

    /// Per weight, more reps than the existing record at that same weight. Weights are keyed
    /// on a 0.25 kg grid so an lb re-entry (60.0004 kg) doesn't open a second "at 60 kg" row.
    /// Assisted sets are skipped: they carry `weightKg == 0` by convention, so counting them
    /// banked "8 reps bodyweight" for a pull-up done with 30 kg of help — and then blocked the
    /// real bodyweight rep PR when the lifter finally did one unassisted. Their record is
    /// `leastAssistance`.
    private static func maxRepsAtWeightRecords(
        sets: [PerformedSet], date: Date, existing: [PersonalRecord]
    ) -> [PersonalRecord] {
        var bestRepsByWeight: [Double: Int] = [:]
        for set in sets where set.reps >= 1 && set.assistanceKg == nil {
            let key = weightKey(set.weightKg)
            let current = bestRepsByWeight[key] ?? 0
            if set.reps > current {
                bestRepsByWeight[key] = set.reps
            }
        }
        var records: [PersonalRecord] = []
        for (weight, reps) in bestRepsByWeight.sorted(by: { $0.key < $1.key }) {
            // `existing` can hold more than one row in the same 0.25 kg bucket (e.g. a pre-rounding
            // 60.0004 kg row beside a 60.0 kg one) — beat the best of them, not just the first match.
            let currentBest = existing
                .filter { $0.kind == .maxRepsAtWeight && weightKey($0.weightKg) == weight }
                .map(\.reps)
                .max()
            if let currentBest, reps <= currentBest { continue }
            records.append(
                PersonalRecord(
                    kind: .maxRepsAtWeight, value: Double(reps), weightKg: weight, reps: reps, date: date
                )
            )
        }
        return records
    }

    private static func weightKey(_ weightKg: Double) -> Double {
        (weightKg / 0.25).rounded() * 0.25
    }

    private static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
