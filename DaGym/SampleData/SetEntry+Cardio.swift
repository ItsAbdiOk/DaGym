import Foundation
import GymCore

/// Cardio reads of a `SetEntry` (plan.md §6.1): a run row carries a time and a distance, each
/// with the same two-state split a timed hold's duration has — the *target* the plan or last
/// session set until the row is ticked, the value actually done after. Pace and speed are
/// derived, never stored.
extension SetEntry {
    /// The time the row shows: what was done, else what was asked for.
    var cardioSeconds: Int? { durationSeconds ?? targetSeconds }

    /// The distance the row shows: what was covered, else what was asked for.
    var cardioMeters: Double? { distanceMeters ?? targetDistanceMeters }

    /// "5:06 /km", or nil until both a time and a distance are on the row.
    func cardioPace(unit: DistanceUnit) -> String? {
        guard let seconds = cardioSeconds, let meters = cardioMeters else { return nil }
        return CardioPace.formatPace(distanceMeters: meters, durationSeconds: seconds, unit: unit)
    }

    /// "11.8 km/h", or nil until both a time and a distance are on the row.
    func cardioSpeed(unit: DistanceUnit) -> String? {
        guard let seconds = cardioSeconds, let meters = cardioMeters else { return nil }
        return CardioPace.formatSpeed(distanceMeters: meters, durationSeconds: seconds, unit: unit)
    }

    /// "5.00 km · 25:30 · 5:06 /km" — the history line for a logged cardio set. Whichever of
    /// time and distance is missing is left out rather than printed as 0.
    func cardioSummary(unit: DistanceUnit) -> String {
        var parts: [String] = []
        if let meters = cardioMeters, meters > 0 { parts.append(unit.formatWithSymbol(meters: meters)) }
        if let seconds = cardioSeconds, seconds > 0 { parts.append(CardioPace.clock(seconds)) }
        if let pace = cardioPace(unit: unit) { parts.append(pace) }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    /// Ticking a cardio row that was never edited logs the targets as done — the lifter ran the
    /// 5 km the plan asked for. Without this the row stayed "0 km · 0:00" in history.
    mutating func adoptCardioTargets() {
        if durationSeconds == nil { durationSeconds = targetSeconds }
        if distanceMeters == nil { distanceMeters = targetDistanceMeters }
    }
}

extension WorkoutExerciseEntry {
    /// Metres covered by completed counting sets of a cardio exercise; 0 for anything else.
    var distanceMeters: Double {
        guard isCardio else { return 0 }
        return sets.filter { $0.isDone && $0.kind.countsTowardStats }
            .reduce(0) { $0 + ($1.distanceMeters ?? 0) }
    }
}

extension WorkoutSession {
    /// Σ distance over completed cardio sets — the "· 5.0 km" beside the volume on the summary.
    var distanceMeters: Double { exercises.reduce(0) { $0 + $1.distanceMeters } }
}

extension WorkoutDetail {
    var distanceMeters: Double { exercises.reduce(0) { $0 + $1.distanceMeters } }
}

extension ExerciseInfo {
    /// Treadmills and stair machines have an incline dial; nothing else does. The cardio row
    /// hides the incline field otherwise until the lifter asks for it.
    var hasInclineByDefault: Bool {
        let kit = equipment.lowercased()
        return kit.contains("treadmill") || kit.contains("stair") || kit.contains("stepmill")
    }
}
