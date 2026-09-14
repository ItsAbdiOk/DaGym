import Foundation

/// Pure unit-conversion and estimate math pulled out of `HealthKitStore` so it's unit-testable
/// without a real `HKHealthStore` — `isAvailable` is false in the unit-test host, so any logic
/// left inside the actor's query closures never runs under `swift test`. See
/// `HealthUnitConversionTests`.
enum HealthUnitConversion {
    /// HealthKit reports body fat as a 0...1 fraction (`HKUnit.percent()`); the app displays a
    /// plain percentage (0...100).
    static func bodyFatPercent(fromFraction fraction: Double) -> Double { fraction * 100 }

    /// A rough MET-based active-energy estimate for a finished strength session, used only when
    /// the user has explicitly turned on "Estimate calories" — no heart-rate sensor backs this
    /// number, so it's clearly a guess (see `HealthWorkoutInput.energyIsEstimate`). 5 METs is
    /// ACSM's general resistance-training figure; kcal = METs × 3.5 × bodyweightKg / 200 per
    /// minute, i.e. METs × bodyweightKg × hours for the whole session.
    static func estimatedActiveEnergyKcal(durationSeconds: Int, bodyweightKg: Double) -> Double {
        let hours = Double(max(0, durationSeconds)) / 3_600
        let safeBodyweight = max(0, bodyweightKg)
        return 5.0 * safeBodyweight * hours
    }
}
