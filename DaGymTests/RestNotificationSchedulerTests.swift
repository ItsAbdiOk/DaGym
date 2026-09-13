import Foundation
import Testing
import UserNotifications

@testable import DaGym

/// A fake `RestNotificationCenter` that just records calls, so these tests assert the
/// scheduler's *decisions* (schedule at endDate, cancel on skip, reschedule on +30 s) without
/// touching the real, permission-gated `UNUserNotificationCenter`.
private final class FakeNotificationCenter: RestNotificationCenter {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []

    func add(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }
}

@MainActor
@Suite("RestNotificationScheduler")
struct RestNotificationSchedulerTests {
    @Test("schedule adds a request that fires at endDate with the next-set body")
    func schedulesAtEndDate() throws {
        let center = FakeNotificationCenter()
        let scheduler = RestNotificationScheduler(center: center)
        let endDate = Date().addingTimeInterval(90)

        scheduler.schedule(endDate: endDate, nextSetLabel: "82.5 × 8")

        #expect(center.addedRequests.count == 1)
        let request = try #require(center.addedRequests.first)
        #expect(request.content.body == "Next: 82.5 × 8")
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(abs(trigger.timeInterval - 90) < 1)
    }

    @Test("schedule cancels any pending request before adding the new one")
    func scheduleCancelsFirst() throws {
        let center = FakeNotificationCenter()
        let scheduler = RestNotificationScheduler(center: center)

        scheduler.schedule(endDate: Date().addingTimeInterval(60), nextSetLabel: "Set 1")

        #expect(center.removedIdentifiers.count == 1)
        #expect(center.addedRequests.count == 1)
    }

    @Test("cancel removes the pending request without scheduling a new one")
    func cancelRemovesPending() throws {
        let center = FakeNotificationCenter()
        let scheduler = RestNotificationScheduler(center: center)
        scheduler.schedule(endDate: Date().addingTimeInterval(60), nextSetLabel: "Set 1")

        scheduler.cancel()

        #expect(center.removedIdentifiers.count == 2)
        #expect(center.addedRequests.count == 1)
    }

    @Test("adjusting rest reschedules: cancels the old request and adds one at the new endDate")
    func rescheduleOnAdjust() throws {
        let center = FakeNotificationCenter()
        let scheduler = RestNotificationScheduler(center: center)
        let firstEnd = Date().addingTimeInterval(60)
        let secondEnd = firstEnd.addingTimeInterval(30)

        scheduler.schedule(endDate: firstEnd, nextSetLabel: "Set 1")
        scheduler.schedule(endDate: secondEnd, nextSetLabel: "Set 1")

        #expect(center.addedRequests.count == 2)
        #expect(center.removedIdentifiers.count == 2)
        let lastRequest = center.addedRequests.last
        let secondTrigger = try #require(lastRequest?.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(abs(secondTrigger.timeInterval - 90) < 1)
    }
}
