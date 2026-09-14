import Foundation
import HealthKit

/// Body composition, recovery signals, external-workout import and background delivery for
/// `HealthKitStore` — split out of `HealthStore.swift` to stay under the file-length lint limit.
/// Everything here relies on members `HealthStore.swift` deliberately left non-`private` (`store`,
/// the type constants, `runQuery`/`quantitySamples`/`latestQuantitySample`, `workoutObserver`)
/// since `private` is file-scoped and this is a separate file.
extension HealthKitStore {
    /// Implausible readings (a scale glitch, another app writing 18 into a 0...1 field) are
    /// dropped rather than shown — see `HealthUnitConversion.isPlausibleBodyFatPercent`.
    func latestBodyFatPercentage() async throws -> HealthSample? {
        let sample = try await latestQuantitySample(type: Self.bodyFatType) { quantity in
            HealthUnitConversion.bodyFatPercent(fromFraction: quantity.doubleValue(for: .percent()))
        }
        guard let sample, HealthUnitConversion.isPlausibleBodyFatPercent(sample.value) else { return nil }
        return sample
    }

    func bodyFatHistory(from: Date, to: Date) async throws -> [HealthSample] {
        try await quantitySamples(type: Self.bodyFatType, from: from, to: to) { quantity in
            HealthUnitConversion.bodyFatPercent(fromFraction: quantity.doubleValue(for: .percent()))
        }
        .filter { HealthUnitConversion.isPlausibleBodyFatPercent($0.value) }
    }

    func latestLeanBodyMass() async throws -> HealthSample? {
        try await latestQuantitySample(type: Self.leanBodyMassType) { quantity in
            quantity.doubleValue(for: .gramUnit(with: .kilo))
        }
    }

    func leanBodyMassHistory(from: Date, to: Date) async throws -> [HealthSample] {
        try await quantitySamples(type: Self.leanBodyMassType, from: from, to: to) { quantity in
            quantity.doubleValue(for: .gramUnit(with: .kilo))
        }
    }

    func latestHeight() async throws -> HealthSample? {
        try await latestQuantitySample(type: Self.heightType) { quantity in
            quantity.doubleValue(for: .meter())
        }
    }

    func hrv(from: Date, to: Date) async throws -> [HealthSample] {
        try await quantitySamples(type: Self.hrvType, from: from, to: to) { quantity in
            quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
        }
    }

    func restingHeartRate(from: Date, to: Date) async throws -> [HealthSample] {
        try await quantitySamples(type: Self.restingHRType, from: from, to: to) { quantity in
            quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
    }

    func sleep(from: Date, to: Date) async throws -> [HealthSleepInterval] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
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

    func externalStrengthWorkouts(since: Date) async throws -> [HealthExternalWorkout] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await runQuery(
            type: Self.workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sort: sort
        ) { samples in
            samples.compactMap { sample -> HealthExternalWorkout? in
                guard let workout = sample as? HKWorkout,
                      Self.strengthActivityTypes.contains(workout.workoutActivityType),
                      workout.metadata?["DaGymWorkoutID"] == nil
                else { return nil }
                return HealthExternalWorkout(
                    uuid: workout.uuid.uuidString, start: workout.startDate, end: workout.endDate,
                    title: Self.activityName(workout.workoutActivityType)
                )
            }
        }
    }

    func observeWorkoutChanges(onChange: @escaping @Sendable () async -> Void) async throws {
        guard isAvailable, workoutObserver == nil else { return }
        try await store.enableBackgroundDelivery(for: Self.workoutType, frequency: .immediate)
        let query = HKObserverQuery(sampleType: Self.workoutType, predicate: nil) { _, completion, _ in
            // `completion()` is HealthKit's "I'm done, you may suspend me" signal, so it has to
            // come *after* the pull. Calling it first (as this did) let iOS suspend the app
            // mid-fetch on a foreground delivery; never calling it at all makes iOS give up on
            // background delivery for this type after a few strikes.
            let done = ObserverCompletion(call: completion)
            Task {
                await onChange()
                done.call()
            }
        }
        workoutObserver = query
        store.execute(query)
    }

    /// HealthKit hands back a plain Objective-C block that carries no `Sendable` annotation,
    /// so Swift 6 refuses to let it cross into the `Task` that awaits the pull. The block is
    /// documented as callable from any thread and holds no state of ours — this box asserts
    /// exactly that and nothing more.
    private struct ObserverCompletion: @unchecked Sendable {
        let call: HKObserverQueryCompletionHandler
    }

    fileprivate static func isAsleep(_ rawValue: Int) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        default: return false
        }
    }

    fileprivate static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: "Strength Training"
        case .functionalStrengthTraining: "Functional Strength Training"
        case .coreTraining: "Core Training"
        default: "Strength Training"
        }
    }
}
