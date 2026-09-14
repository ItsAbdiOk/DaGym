import Foundation
import Testing

@testable import DaGym

/// Records the order in which an observer delivery's two halves ran.
private actor DeliveryLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

/// `HealthKitStore.deliver` is the body of the `HKObserverQuery` handler: it has to run the pull
/// to completion *before* calling HealthKit's completion handler. Calling completion first let
/// iOS suspend the app mid-fetch on a foreground delivery, and the old test for this only ever
/// asserted on a flag the fake itself set — it could not fail. This one runs the real wrapper.
@Suite("HealthKitStore observer delivery")
struct ServiceHealthObserverTests {
    @Test("the completion handler is signalled only after the pull has finished")
    func completionFollowsThePull() async throws {
        let log = DeliveryLog()

        let task = HealthKitStore.deliver(
            onChange: {
                // Long enough that a completion fired "first" would land well before it.
                try? await Task.sleep(for: .milliseconds(50))
                await log.record("pull")
            },
            completion: { Task { await log.record("completion") } }
        )
        await task.value
        // `completion` hops through its own Task; give it a moment to land.
        try await Task.sleep(for: .milliseconds(50))

        let events = await log.events
        #expect(events == ["pull", "completion"])
    }

    @Test("every delivery calls completion exactly once")
    func completionIsCalledOnce() async throws {
        let log = DeliveryLog()

        await HealthKitStore.deliver(
            onChange: { await log.record("pull") },
            completion: { Task { await log.record("completion") } }
        ).value
        try await Task.sleep(for: .milliseconds(50))

        let events = await log.events
        #expect(events.filter { $0 == "completion" }.count == 1)
    }
}
