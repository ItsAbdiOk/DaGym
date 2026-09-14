import Foundation

/// Pure unit-conversion and estimate math pulled out of `HealthKitStore` so it's unit-testable
/// without a real `HKHealthStore` — `isAvailable` is false in the unit-test host, so any logic
/// left inside the actor's query closures never runs under `swift test`. See
/// `HealthUnitConversionTests`.
enum HealthUnitConversion {
    /// HealthKit reports body fat as a 0...1 fraction (`HKUnit.percent()`); the app displays a
    /// plain percentage (0...100).
    static func bodyFatPercent(fromFraction fraction: Double) -> Double { fraction * 100 }

    /// False for a body fat reading that can't be real — a scale glitch, a unit mix-up, or a
    /// sample another app wrote as a whole number into a fraction field (0.18 vs 18). A tile
    /// showing "1800%" is worse than no tile, so callers drop the sample entirely.
    static func isPlausibleBodyFatPercent(_ percent: Double) -> Bool {
        percent > 0 && percent <= 100
    }

    /// Net MET value for resistance training: ACSM puts general resistance training at about
    /// 5 METs, and *active* energy is energy above resting, which is 1 MET by definition — so the
    /// figure that belongs in `activeEnergyBurned` is 5 − 1, not 5. Writing the gross number
    /// over-reported every session by about 25%.
    static let netResistanceTrainingMETs = 4.0

    /// A rough MET-based active-energy estimate for a finished strength session, used only when
    /// the user has explicitly turned on "Estimate calories" — no heart-rate sensor backs this
    /// number, so it's clearly a guess (see `HealthWorkoutInput.energyIsEstimate`).
    /// kcal = METs × 3.5 × bodyweightKg / 200 per minute, i.e. METs × bodyweightKg × hours.
    ///
    /// Nil rather than zero when there is nothing worth writing: a zero/negative duration, a
    /// zero/negative bodyweight, or anything that rounds to under 1 kcal. HealthKit will happily
    /// store a 0 kcal sample, and a workout littered with those is noise in the user's Health app.
    static func estimatedActiveEnergyKcal(durationSeconds: Int, bodyweightKg: Double) -> Double? {
        guard durationSeconds > 0, bodyweightKg > 0 else { return nil }
        let hours = Double(durationSeconds) / 3_600
        let kcal = netResistanceTrainingMETs * bodyweightKg * hours
        return kcal >= 1 ? kcal : nil
    }
}
