import Foundation
import GymCore

/// Everything the workout share card draws, already formatted for the user's units (plan.md
/// §6.4 "share"). Pure value type built from a `WorkoutSummary` so the strings can be unit
/// tested without rendering. Nothing here is HealthKit-derived: duration, sets, volume, PRs and
/// muscles all come from the logged sets alone.
struct ShareCardModel: Equatable {
    /// One of the top muscles worked, with its share of the session's total engagement.
    struct MuscleShare: Equatable {
        var muscle: Muscle
        var share: Double

        var percentText: String { "\(Int((share * 100).rounded()))%" }
    }

    var title: String
    var dateText: String
    var durationText: String
    var setsText: String
    /// "6 840 kg" — grouped with a thin space, in the user's unit.
    var volumeText: String
    /// "5.0 km" once a run is in the session; nil otherwise.
    var distanceText: String?
    /// "1 Personal Record" / "3 Personal Records"; nil when there were none.
    var prHeadline: String?
    /// "Bench · 82.5 × 8 (e1RM 102.5)" per PR, in summary order.
    var prLines: [String]
    var musclesHit: [Muscle: Double]
    var topMuscles: [MuscleShare]

    init(
        summary: WorkoutSummary, title: String, date: Date = Date(), unit: WeightUnit,
        distanceUnit: DistanceUnit, calendar: Calendar = .current
    ) {
        self.title = title
        dateText = date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: calendar)
        )
        // Same "m:ss" as `WorkoutSession.clock`, which is main-actor bound and this model is not.
        durationText = String(format: "%d:%02d", summary.durationSeconds / 60, summary.durationSeconds % 60)
        setsText = "\(summary.setsDone)"
        volumeText = "\(Self.volumeText(kg: summary.volumeKg, unit: unit)) \(unit.symbol)"
        distanceText = summary.distanceMeters > 0
            ? distanceUnit.formatWithSymbol(meters: summary.distanceMeters, decimals: 1)
            : nil
        prHeadline = Self.prHeadline(count: summary.prs.count)
        prLines = summary.prs.map { "\($0.exerciseName) · \($0.line)" }
        musclesHit = summary.musclesHit
        topMuscles = Self.topMuscles(summary.musclesHit)
    }

    // MARK: - Share sheet copy

    /// The share sheet's subject line (Mail) — "Push A · DaGym".
    var shareSubject: String { "\(title) · DaGym" }

    /// The message beside the image — headline numbers plus the PR count, one line.
    var shareMessage: String {
        var parts = ["\(title) — \(durationText), \(setsText) sets, \(volumeText)"]
        if let distanceText { parts[0] += ", \(distanceText)" }
        if let prHeadline { parts.append(prHeadline.lowercased()) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Formatting

    /// A large kg total in `unit`, thin-space grouped, no decimals — the same shape as
    /// `Preferences.formatVolume` (which is main-actor bound, hence the copy here).
    static func volumeText(kg: Double, unit: WeightUnit) -> String {
        let display = unit.display(kg: kg)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: display)) ?? "\(Int(display))"
    }

    static func prHeadline(count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 Personal Record"
        default: "\(count) Personal Records"
        }
    }

    /// The three muscles with the largest share of the session's engagement, largest first.
    /// Ties break on the muscle's name so the card is deterministic.
    static func topMuscles(_ musclesHit: [Muscle: Double]) -> [MuscleShare] {
        let total = musclesHit.values.reduce(0, +)
        guard total > 0 else { return [] }
        return musclesHit
            .sorted { $0.value == $1.value ? $0.key.displayName < $1.key.displayName : $0.value > $1.value }
            .prefix(3)
            .map { MuscleShare(muscle: $0.key, share: $0.value / total) }
    }
}
