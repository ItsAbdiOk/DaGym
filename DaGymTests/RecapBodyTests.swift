import Foundation
import GymCore
import Testing

@testable import DaGym

/// X2/T: the weekly-recap notification body was built with a hard-coded " kg" literal
/// regardless of `Preferences.weightUnit` — a lb user's Sunday-evening push always read in kg.
/// `TrainingNotificationScheduler.recapBody(_:unit:)` now takes the unit like the rest of the
/// kg-formatting call sites the review flagged (F8's `PrescriptionReason` pattern).
@MainActor
@Suite("Recap body unit formatting")
struct RecapBodyTests {
    private func recap(volumeKg: Double) -> WeeklyRecap {
        WeeklyRecap(
            weekStart: Date(), weeklyGoal: 4, workouts: 3, sets: 21, volumeKg: volumeKg, prs: 2,
            workoutsDelta: 1, setsDelta: 2, prsDelta: 1, volumeDeltaPercent: 12
        )
    }

    @Test("defaults to kg")
    func defaultsToKg() {
        let body = TrainingNotificationScheduler.recapBody(recap(volumeKg: 1000))
        #expect(body.contains("kg"))
        #expect(!body.contains("lb"))
    }

    @Test("renders in lb when the user's display unit is lb")
    func rendersInPounds() {
        // 1000 kg ≈ 2205 lb.
        let body = TrainingNotificationScheduler.recapBody(recap(volumeKg: 1000), unit: .lb)
        #expect(body.contains("lb"))
        #expect(!body.contains(" kg"))
        #expect(body.contains("2\u{2009}205") || body.contains("2205") || body.contains("2\u{202f}205"))
    }
}
