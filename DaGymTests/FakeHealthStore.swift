import Foundation

@testable import DaGym

/// In-memory `HealthStoring` double for `HealthSyncServiceTests`. Records every call so a test
/// can assert on what was (or wasn't) written, and lets a test seed what a "read" returns.
actor FakeHealthStore: HealthStoring {
    nonisolated let isAvailable: Bool

    private(set) var savedWorkouts: [HealthWorkoutInput] = []
    private(set) var savedBodyMasses: [HealthBodyMass] = []
    private(set) var deletedWorkoutIDs: [String] = []
    private(set) var authorizationRequested = false
    private(set) var workoutObserverRegistered = false
    var bodyMassToReturn: HealthBodyMass?
    var bodyMassHistoryToReturn: [HealthSample] = []
    var bodyFatToReturn: HealthSample?
    var bodyFatHistoryToReturn: [HealthSample] = []
    var leanBodyMassToReturn: HealthSample?
    var leanBodyMassHistoryToReturn: [HealthSample] = []
    var heightToReturn: HealthSample?
    var hrvToReturn: [HealthSample] = []
    var restingHeartRateToReturn: [HealthSample] = []
    var sleepToReturn: [HealthSleepInterval] = []
    var externalWorkoutsToReturn: [HealthExternalWorkout] = []
    var authorizationRequestToReturn: HealthAuthorizationRequest = .alreadyRequested
    var sharingAuthorizationToReturn: HealthShareAuthorization = .authorized
    private var nextWorkoutID = 0
    /// The `HKObserverQuery` handler `observeWorkoutChanges` was registered with, so a test can
    /// fire the observer the way HealthKit would. Nil until registration.
    private var workoutOnChange: (@Sendable () async -> Void)?

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func setBodyMassToReturn(_ value: HealthBodyMass?) {
        bodyMassToReturn = value
    }

    func setBodyMassHistoryToReturn(_ values: [HealthSample]) {
        bodyMassHistoryToReturn = values
    }

    func setExternalWorkoutsToReturn(_ values: [HealthExternalWorkout]) {
        externalWorkoutsToReturn = values
    }

    func setBodyFatToReturn(_ value: HealthSample?, history: [HealthSample] = []) {
        bodyFatToReturn = value
        bodyFatHistoryToReturn = history
    }

    func setLeanBodyMassToReturn(_ value: HealthSample?, history: [HealthSample] = []) {
        leanBodyMassToReturn = value
        leanBodyMassHistoryToReturn = history
    }

    func setHeightToReturn(_ value: HealthSample?) {
        heightToReturn = value
    }

    func setRecoverySamples(
        restingHeartRate: [HealthSample] = [], hrv: [HealthSample] = [], sleep: [HealthSleepInterval] = []
    ) {
        restingHeartRateToReturn = restingHeartRate
        hrvToReturn = hrv
        sleepToReturn = sleep
    }

    func setAuthorizationRequestToReturn(_ value: HealthAuthorizationRequest) {
        authorizationRequestToReturn = value
    }

    func setSharingAuthorizationToReturn(_ value: HealthShareAuthorization) {
        sharingAuthorizationToReturn = value
    }

    /// Fires the registered workout observer's handler and waits for it to finish, the way
    /// `HealthKitStore.deliver` does before it signals HealthKit's completion handler. Returns
    /// false when nothing is registered. (The pull-then-complete ordering itself is pinned down
    /// by `ServiceHealthObserverTests`, against the real `deliver`.)
    @discardableResult
    func triggerWorkoutChange() async -> Bool {
        guard let workoutOnChange else { return false }
        await workoutOnChange()
        return true
    }

    func requestAuthorization() async throws {
        authorizationRequested = true
    }

    func authorizationRequestStatus() async -> HealthAuthorizationRequest {
        authorizationRequestToReturn
    }

    func sharingAuthorization(for type: HealthShareType) async -> HealthShareAuthorization {
        sharingAuthorizationToReturn
    }

    func saveWorkout(_ input: HealthWorkoutInput) async throws -> String {
        savedWorkouts.append(input)
        nextWorkoutID += 1
        return "fake-hk-\(nextWorkoutID)"
    }

    func deleteOwnWorkout(healthKitID: String) async throws {
        deletedWorkoutIDs.append(healthKitID)
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        savedBodyMasses.append(HealthBodyMass(kg: kg, date: date))
    }

    func latestBodyMass() async throws -> HealthBodyMass? {
        bodyMassToReturn
    }

    func bodyMassHistory(from: Date, to: Date) async throws -> [HealthSample] {
        bodyMassHistoryToReturn
    }

    func latestBodyFatPercentage() async throws -> HealthSample? { bodyFatToReturn }

    func bodyFatHistory(from: Date, to: Date) async throws -> [HealthSample] {
        bodyFatHistoryToReturn
    }

    func latestLeanBodyMass() async throws -> HealthSample? { leanBodyMassToReturn }

    func leanBodyMassHistory(from: Date, to: Date) async throws -> [HealthSample] {
        leanBodyMassHistoryToReturn
    }

    func latestHeight() async throws -> HealthSample? { heightToReturn }

    func hrv(from: Date, to: Date) async throws -> [HealthSample] { hrvToReturn }

    func restingHeartRate(from: Date, to: Date) async throws -> [HealthSample] { restingHeartRateToReturn }

    func sleep(from: Date, to: Date) async throws -> [HealthSleepInterval] { sleepToReturn }

    func externalStrengthWorkouts(since: Date) async throws -> [HealthExternalWorkout] {
        externalWorkoutsToReturn
    }

    func observeWorkoutChanges(onChange: @escaping @Sendable () async -> Void) async throws {
        workoutObserverRegistered = true
        workoutOnChange = onChange
    }
}
