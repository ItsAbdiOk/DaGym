import Foundation
import HealthKit

/// One point-in-time reading of a Health quantity type — HRV, resting heart rate, body mass,
/// body fat %, lean body mass or height — returned by every date-ranged/latest read on
/// `HealthStoring`. What `value` means depends on which method returned it (kg, ms, bpm, %, m).
struct HealthSample: Sendable, Equatable {
    var date: Date
    var value: Double
}

/// One asleep interval (`HealthStoring.sleep`) — asleep time only, never "in bed".
struct HealthSleepInterval: Sendable, Equatable {
    var start: Date
    var end: Date
}

/// A bodyweight reading (`HealthStoring.latestBodyMass`).
struct HealthBodyMass: Sendable, Equatable {
    var kg: Double
    var date: Date
}

/// One `HKWorkout` logged by another app (Watch, a third-party trainer app, etc.) that looks
/// like strength training. Never one of ours — `HealthKitStore.externalStrengthWorkouts` filters
/// out anything carrying our own `DaGymWorkoutID` metadata before it ever reaches this struct.
struct HealthExternalWorkout: Sendable, Equatable {
    /// `HKWorkout.uuid.uuidString` — the dedupe key. Stored on `ImportedHealthWorkoutModel` in
    /// the always-local Health store once imported (and tombstoned there if the user deletes it),
    /// so a later pull never imports the same sample twice or resurrects a deleted one.
    var uuid: String
    var start: Date
    var end: Date
    var title: String
}

enum HealthStoreError: Error {
    case unavailable
    case saveFailed
}

/// Whether HealthKit has ever shown its permission sheet for the types DaGym asks for.
/// HealthKit deliberately never reveals whether a *read* was granted or denied — a denied read
/// looks exactly like "no data". This is the one thing it will say, and it's enough to tell
/// "we've never asked" apart from "we asked and got nothing back", which is what the UI needs to
/// choose between staying quiet and offering "Check Health permissions".
enum HealthAuthorizationRequest: Sendable, Equatable {
    /// Health is unavailable, or the status couldn't be determined.
    case unknown
    /// The sheet has never been shown for at least one of our types.
    case shouldRequest
    /// Every type has been put to the user already. Silence now means no data *or* a denied read.
    case alreadyRequested
}

/// The three things DaGym can write to Health, for `HealthStoring.sharingAuthorization(for:)`.
/// Unlike reads, write permission is readable — which is what lets onboarding avoid leaving a
/// "Save workouts to Health" toggle on after the user said no.
enum HealthShareType: Sendable, Equatable {
    case workouts
    case bodyMass
    case activeEnergy
}

enum HealthShareAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
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
    /// Active energy to attach to the `HKWorkout`, or nil to write none — see `energyIsEstimate`
    /// and the comment on `saveWorkout` for when each is appropriate.
    var energyKcal: Double?
    /// True when `energyKcal` is a guess (`Preferences.healthEstimateCalories`), not a real
    /// heart-rate-derived reading. Marked on the written sample with `HKMetadataKeyWasUserEntered`
    /// plus our own `DaGymEnergyIsEstimate` key, so anything reading Health back can tell the
    /// difference. Meaningless when `energyKcal` is nil.
    var energyIsEstimate: Bool = false
}

/// Everything `HealthSyncService` needs from Apple Health, abstracted so it can be exercised with
/// `FakeHealthStore` (DaGymTests) instead of a real `HKHealthStore`. Every method is safe to call
/// even when Health isn't available or authorization hasn't been granted — they no-op or throw,
/// never crash. `HealthKitStore` below is the real implementation; see plan.md §6.8.
protocol HealthStoring: Sendable {
    /// False on a device with no Health app (e.g. an iPad build), where every other call is a no-op.
    var isAvailable: Bool { get }

    /// Requests every read/write type this feature ever touches in one sheet: share (write) body
    /// mass, workouts and active energy; read body mass, body fat %, lean body mass, height, HRV,
    /// resting heart rate, sleep and workouts (to find ones logged in other apps). The per-type
    /// toggles in `HealthSettingsView` control what DaGym actually *uses*, independent of this grant.
    func requestAuthorization() async throws

    /// Whether the permission sheet has already been shown for every type DaGym asks for
    /// (`HKHealthStore.statusForAuthorizationRequest`). Never throws — an error reads as
    /// `.unknown`, which the UI treats the same as "don't say anything yet".
    func authorizationRequestStatus() async -> HealthAuthorizationRequest

    /// Whether the user granted, denied, or was never asked for permission to *write* one type.
    /// HealthKit exposes this for shares only; reads are deliberately opaque.
    func sharingAuthorization(for type: HealthShareType) async -> HealthShareAuthorization

    /// Saves one finished strength session as an `HKWorkout` (activity `.traditionalStrengthTraining`)
    /// and returns its `HKWorkout.uuid` string, so the caller can record it on `WorkoutModel.healthKitID`
    /// and never save the same workout twice. `HealthWorkoutInput.energyKcal` is nil unless the
    /// user turned on "Estimate calories" — plan.md §6.8 and the owner's brief are explicit that
    /// calories must come from real heart-rate data, which this app doesn't have outside a Watch
    /// session (P5). When a caller does have a real heart-rate-derived energy figure, it's passed
    /// here too, with `energyIsEstimate: false`.
    func saveWorkout(_ input: HealthWorkoutInput) async throws -> String

    /// Deletes the `HKWorkout` DaGym itself wrote for `healthKitID` (matched on our own
    /// `DaGymWorkoutID` metadata as well as the uuid, so this can never touch another app's
    /// sample). Called when the workout is deleted here — "Never duplicated" in the settings copy
    /// has to mean the Health side dies with it. A no-op when the sample is already gone.
    func deleteOwnWorkout(healthKitID: String) async throws

    func saveBodyMass(kg: Double, date: Date) async throws
    func latestBodyMass() async throws -> HealthBodyMass?
    /// Every body mass sample in the window, oldest first — backs the bodyweight chart and trend
    /// logic with full Health history, not just the latest reading.
    func bodyMassHistory(from: Date, to: Date) async throws -> [HealthSample]

    func latestBodyFatPercentage() async throws -> HealthSample?
    func bodyFatHistory(from: Date, to: Date) async throws -> [HealthSample]

    func latestLeanBodyMass() async throws -> HealthSample?
    func leanBodyMassHistory(from: Date, to: Date) async throws -> [HealthSample]

    func latestHeight() async throws -> HealthSample?

    func hrv(from: Date, to: Date) async throws -> [HealthSample]
    func restingHeartRate(from: Date, to: Date) async throws -> [HealthSample]
    func sleep(from: Date, to: Date) async throws -> [HealthSleepInterval]

    /// `HKWorkout` samples that look like strength training, logged since `since`, excluding
    /// anything DaGym itself wrote (filtered on `DaGymWorkoutID` metadata). Oldest first.
    func externalStrengthWorkouts(since: Date) async throws -> [HealthExternalWorkout]

    /// Registers for background delivery of new `HKWorkout` samples and starts an
    /// `HKObserverQuery` that runs `onChange` whenever one lands — including from another app or
    /// device. Safe to call more than once; only the first registration takes effect.
    ///
    /// `onChange` is `async` on purpose: HealthKit hands the observer a completion handler that
    /// must only be called once the work is *finished*. Calling it early lets iOS suspend the app
    /// mid-fetch, and missing it entirely makes iOS stop delivering after a few strikes. The
    /// implementation awaits `onChange` and calls the completion handler after it returns.
    func observeWorkoutChanges(onChange: @escaping @Sendable () async -> Void) async throws
}

/// The real `HealthStoring`, wrapping `HKHealthStore`. An actor: every call already hops off the
/// main thread for HealthKit's own I/O, and isolating here keeps `HKHealthStore`/`HKWorkoutBuilder`
/// instances from ever needing to be `Sendable` themselves — only the plain-value results
/// (`HealthSample`, `HealthBodyMass`, `String`) cross back out.
actor HealthKitStore: HealthStoring {
    /// The one instance the app uses. `HKObserverQuery` registration is per-`HealthKitStore`
    /// (`workoutObserver` is what makes a second `observeWorkoutChanges` call a no-op), so
    /// every `HealthSyncService`/`HealthInsightsService` sharing this instance is what keeps the
    /// app-delegate registration and a Settings toggle flip from starting two observers on the
    /// same type.
    static let shared = HealthKitStore()
    // Not `private`: `HealthKitStore+Read.swift` holds roughly half of this actor's methods
    // (moved there to stay under the file-length lint limit) and needs to reach `store` and the
    // type constants below — `private` is file-scoped in Swift, so a same-actor extension in a
    // different file can't see a `private` member. Still actor-isolated and still internal to
    // the module, so nothing outside `HealthKitStore` itself can touch these either way.
    let store = HKHealthStore()

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let bodyMassType = HKQuantityType(.bodyMass)
    static let bodyFatType = HKQuantityType(.bodyFatPercentage)
    static let leanBodyMassType = HKQuantityType(.leanBodyMass)
    static let heightType = HKQuantityType(.height)
    static let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    static let restingHRType = HKQuantityType(.restingHeartRate)
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    static let sleepType = HKCategoryType(.sleepAnalysis)
    static let workoutType = HKObjectType.workoutType()
    static let strengthActivityTypes: Set<HKWorkoutActivityType> = [
        .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining
    ]
    private static let readTypes: Set<HKObjectType> = [
        bodyMassType, bodyFatType, leanBodyMassType, heightType, hrvType, restingHRType, sleepType,
        workoutType
    ]
    private static let writeTypes: Set<HKSampleType> = [bodyMassType, workoutType, activeEnergyType]

    /// Kept alive for as long as this actor lives, so the `HKObserverQuery` isn't deallocated
    /// (and silently stops firing) the moment `observeWorkoutChanges` returns, and so a second
    /// call is a no-op. `nil` until first registered. Not `private`: set from
    /// `HealthKitStore+Read.swift`,
    /// which holds the observer methods (kept out of this file to stay under the file-length
    /// lint limit) — `private` is file-scoped in Swift, so a same-module extension can't see it.
    var workoutObserver: HKObserverQuery?
    /// True while `observeWorkoutChanges` is suspended in `enableBackgroundDelivery`, so a
    /// reentrant second call doesn't register a second query — see that method.
    var isRegisteringWorkoutObserver = false

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
    }

    func authorizationRequestStatus() async -> HealthAuthorizationRequest {
        guard isAvailable else { return .unknown }
        guard let status = try? await store.statusForAuthorizationRequest(
            toShare: Self.writeTypes, read: Self.readTypes
        ) else { return .unknown }
        switch status {
        case .shouldRequest: return .shouldRequest
        case .unnecessary: return .alreadyRequested
        default: return .unknown
        }
    }

    func sharingAuthorization(for type: HealthShareType) async -> HealthShareAuthorization {
        guard isAvailable else { return .notDetermined }
        switch store.authorizationStatus(for: Self.shareType(type)) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        default: return .notDetermined
        }
    }

    private static func shareType(_ type: HealthShareType) -> HKSampleType {
        switch type {
        case .workouts: workoutType
        case .bodyMass: bodyMassType
        case .activeEnergy: activeEnergyType
        }
    }

    func saveWorkout(_ input: HealthWorkoutInput) async throws -> String {
        guard isAvailable else { throw HealthStoreError.unavailable }
        // `HKWorkoutBuilder.finishWorkout()` throws when the collection is empty in time, which a
        // backfilled session dated "30 minutes, zero seconds ago" or a mis-entered duration can
        // produce. One second is enough to make the sample valid, and is honest about what it is.
        let end = max(input.end, input.start.addingTimeInterval(1))
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
        if let energyKcal = input.energyKcal {
            try await builder.addSamples([Self.energySample(input: input, end: end, kcal: energyKcal)])
        }
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { throw HealthStoreError.saveFailed }
        return workout.uuid.uuidString
    }

    private static func energySample(
        input: HealthWorkoutInput, end: Date, kcal: Double
    ) -> HKQuantitySample {
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        var metadata: [String: Any] = [
            "DaGymWorkoutID": input.workoutID, "DaGymEnergyIsEstimate": input.energyIsEstimate
        ]
        if input.energyIsEstimate {
            metadata[HKMetadataKeyWasUserEntered] = true
        }
        return HKQuantitySample(
            type: activeEnergyType, quantity: quantity, start: input.start, end: end,
            metadata: metadata
        )
    }

    /// Deletes the `HKWorkout` we wrote for this id. The predicate is the sample's own uuid
    /// *and* the presence of our `DaGymWorkoutID` metadata, so a uuid collision (or a
    /// `healthKitID` that somehow points at another app's sample) can't delete someone else's
    /// data. HealthKit itself also refuses to delete objects this app didn't save.
    func deleteOwnWorkout(healthKitID: String) async throws {
        guard isAvailable, let uuid = UUID(uuidString: healthKitID) else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObject(with: uuid),
            HKQuery.predicateForObjects(withMetadataKey: "DaGymWorkoutID")
        ])
        _ = try await store.deleteObjects(of: Self.workoutType, predicate: predicate)
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

    func bodyMassHistory(from: Date, to: Date) async throws -> [HealthSample] {
        try await quantitySamples(type: Self.bodyMassType, from: from, to: to) { quantity in
            quantity.doubleValue(for: .gramUnit(with: .kilo))
        }
    }

    // MARK: - Helpers

    /// Not `private` — see the comment on `store` above; used from both this file and
    /// `HealthKitStore+Read.swift`.
    func quantitySamples(
        type: HKQuantityType, from: Date, to: Date, value: @escaping @Sendable (HKQuantity) -> Double
    ) async throws -> [HealthSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
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

    func latestQuantitySample(
        type: HKQuantityType, value: @escaping @Sendable (HKQuantity) -> Double
    ) async throws -> HealthSample? {
        guard isAvailable else { return nil }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return try await runQuery(type: type, predicate: nil, limit: 1, sort: sort) { samples in
            guard let sample = samples.first as? HKQuantitySample else { return nil }
            return HealthSample(date: sample.endDate, value: value(sample.quantity))
        }
    }

    /// Bridges the completion-handler-only `HKSampleQuery` to `async`, mapping the raw (non-
    /// `Sendable`) `[HKSample]` down to a `Sendable` result *inside* the completion handler so
    /// nothing but plain values ever crosses back into this actor. Not `private` — see the
    /// comment on `store` above.
    func runQuery<T: Sendable>(
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
