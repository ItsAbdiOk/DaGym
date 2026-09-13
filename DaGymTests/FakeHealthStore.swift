import Foundation

@testable import DaGym

/// In-memory `HealthStoring` double for `HealthSyncServiceTests`. Records every call so a test
/// can assert on what was (or wasn't) written, and lets a test seed what a "read" returns.
actor FakeHealthStore: HealthStoring {
    nonisolated let isAvailable: Bool

    private(set) var savedWorkouts: [HealthWorkoutInput] = []
    private(set) var savedBodyMasses: [HealthBodyMass] = []
    private(set) var authorizationRequested = false
    var bodyMassToReturn: HealthBodyMass?
    private var nextWorkoutID = 0

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func setBodyMassToReturn(_ value: HealthBodyMass?) {
        bodyMassToReturn = value
    }

    func requestAuthorization() async throws {
        authorizationRequested = true
    }

    func saveWorkout(_ input: HealthWorkoutInput) async throws -> String {
        savedWorkouts.append(input)
        nextWorkoutID += 1
        return "fake-hk-\(nextWorkoutID)"
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        savedBodyMasses.append(HealthBodyMass(kg: kg, date: date))
    }

    func latestBodyMass() async throws -> HealthBodyMass? {
        bodyMassToReturn
    }

    func recentHRV(days: Int) async throws -> [HealthSample] { [] }

    func recentRestingHeartRate(days: Int) async throws -> [HealthSample] { [] }

    func recentSleep(days: Int) async throws -> [HealthSleepInterval] { [] }
}
