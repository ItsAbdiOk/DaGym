import Foundation
import HealthKit

/// One HRV or resting-heart-rate reading (`HealthStoring.recentHRV`/`recentRestingHeartRate`).
struct HealthSample: Sendable, Equatable {
    var date: Date
    var value: Double
}

/// One asleep interval (`HealthStoring.recentSleep`) — asleep time only, never "in bed".
struct HealthSleepInterval: Sendable, Equatable {
    var start: Date
    var end: Date
}

/// A bodyweight reading (`HealthStoring.latestBodyMass`).
struct HealthBodyMass: Sendable, Equatable {
    var kg: Double
    var date: Date
}

enum HealthStoreError: Error {
    case unavailable
    case saveFailed
}

/// Everything `saveWorkout` needs, bundled into one value so the method stays under the lint
/// parameter-count limit.
struct HealthWorkoutInput: Sendable {
    var start: Date
    var end: Date
    var title: String
    var routineName: String
    var workoutID: String
    var setCount: Int
    var volumeKg: Double
}

/// Everything `HealthSyncService` needs from Apple Health, abstracted so it can be exercised with
/// `FakeHealthStore` (DaGymTests) instead of a real `HKHealthStore`. Every method is safe to call
/// even when Health isn't available or authorization hasn't been granted — they no-op or throw,
/// never crash. `HealthKitStore` below is the real implementation; see plan.md §6.8.
protocol HealthStoring: Sendable {
    /// False on a device with no Health app (e.g. an iPad build), where every other call is a no-op.
    var isAvailable: Bool { get }

    /// Requests every read/write type this feature ever touches in one sheet: share (write) body
    /// mass and workouts, read body mass, HRV, resting heart rate and sleep. The per-type toggles
    /// in `HealthSettingsView` control what DaGym actually *uses*, independent of this grant.
    func requestAuthorization() async throws

    /// Saves one finished strength session as an `HKWorkout` (activity `.traditionalStrengthTraining`)
    /// and returns its `HKWorkout.uuid` string, so the caller can record it on `WorkoutModel.healthKitID`
    /// and never save the same workout twice. No active-energy estimate is written: plan.md §6.8 and
    /// the owner's brief are explicit that calories must come from real heart-rate data, which this
    /// app doesn't have outside a Watch session (P5) — writing a guessed number would misinform
    /// anyone cross-referencing Health against a real energy sensor.
    func saveWorkout(_ input: HealthWorkoutInput) async throws -> String

    func saveBodyMass(kg: Double, date: Date) async throws
    func latestBodyMass() async throws -> HealthBodyMass?
    func recentHRV(days: Int) async throws -> [HealthSample]
    func recentRestingHeartRate(days: Int) async throws -> [HealthSample]
    func recentSleep(days: Int) async throws -> [HealthSleepInterval]
}

/// The real `HealthStoring`, wrapping `HKHealthStore`. An actor: every call already hops off the
/// main thread for HealthKit's own I/O, and isolating here keeps `HKHealthStore`/`HKWorkoutBuilder`
/// instances from ever needing to be `Sendable` themselves — only the plain-value results
/// (`HealthSample`, `HealthBodyMass`, `String`) cross back out.
actor HealthKitStore: HealthStoring {
    private let store = HKHealthStore()

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let bodyMassType = HKQuantityType(.bodyMass)
    private static let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private static let restingHRType = HKQuantityType(.restingHeartRate)
    private static let sleepType = HKCategoryType(.sleepAnalysis)
    private static let workoutType = HKObjectType.workoutType()
    private static let readTypes: Set<HKObjectType> = [bodyMassType, hrvType, restingHRType, sleepType]
    private static let writeTypes: Set<HKSampleType> = [bodyMassType, workoutType]

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
    }

    func saveWorkout(_ input: HealthWorkoutInput) async throws -> String {
        guard isAvailable else { throw HealthStoreError.unavailable }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: input.start)
        try await builder.addMetadata([
            "DaGymWorkoutID": input.workoutID,
            "DaGymRoutineName": input.routineName,
            "DaGymSetCount": input.setCount,
            "DaGymVolumeKg": input.volumeKg,
            HKMetadataKeyWorkoutBrandName: input.title
        ])
        try await builder.endCollection(at: input.end)
        guard let workout = try await builder.finishWorkout() else { throw HealthStoreError.saveFailed }
        return workout.uuid.uuidString
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: Self.bodyMassType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }

    func latestBodyMass() async throws -> HealthBodyMass? {
        guard isAvailable else { return nil }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return try await runQuery(type: Self.bodyMassType, predicate: nil, limit: 1, sort: sort) { samples in
            guard let sample = samples.first as? HKQuantitySample else { return nil }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            return HealthBodyMass(kg: kg, date: sample.endDate)
        }
    }

    func recentHRV(days: Int) async throws -> [HealthSample] {
        try await recentQuantitySamples(type: Self.hrvType, days: days) { quantity in
            quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
        }
    }

    func recentRestingHeartRate(days: Int) async throws -> [HealthSample] {
        try await recentQuantitySamples(type: Self.restingHRType, days: days) { quantity in
            quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
    }

    func recentSleep(days: Int) async throws -> [HealthSleepInterval] {
        guard isAvailable else { return [] }
        let predicate = Self.recentPredicate(days: days)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await runQuery(
            type: Self.sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sort: sort
        ) { samples in
            samples.compactMap { sample -> HealthSleepInterval? in
                guard let category = sample as? HKCategorySample, Self.isAsleep(category.value) else {
                    return nil
                }
                return HealthSleepInterval(start: category.startDate, end: category.endDate)
            }
        }
    }

    // MARK: - Helpers

    private func recentQuantitySamples(
        type: HKQuantityType, days: Int, value: @escaping @Sendable (HKQuantity) -> Double
    ) async throws -> [HealthSample] {
        guard isAvailable else { return [] }
        let predicate = Self.recentPredicate(days: days)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await runQuery(
            type: type, predicate: predicate, limit: HKObjectQueryNoLimit, sort: sort
        ) { samples in
            samples.compactMap { sample in
                guard let quantitySample = sample as? HKQuantitySample else { return nil }
                return HealthSample(date: quantitySample.startDate, value: value(quantitySample.quantity))
            }
        }
    }

    private static func recentPredicate(days: Int) -> NSPredicate {
        let start = Date().addingTimeInterval(-Double(days) * 86_400)
        return HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    }

    private static func isAsleep(_ rawValue: Int) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        default: return false
        }
    }

    /// Bridges the completion-handler-only `HKSampleQuery` to `async`, mapping the raw (non-
    /// `Sendable`) `[HKSample]` down to a `Sendable` result *inside* the completion handler so
    /// nothing but plain values ever crosses back into this actor.
    private func runQuery<T: Sendable>(
        type: HKSampleType, predicate: NSPredicate?, limit: Int, sort: [NSSortDescriptor],
        map: @escaping @Sendable ([HKSample]) -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: map(samples ?? []))
            }
            store.execute(query)
        }
    }
}
