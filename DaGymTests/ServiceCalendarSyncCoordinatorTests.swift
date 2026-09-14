import Foundation
import SwiftData
import Testing

@testable import DaGym

/// The launch / foreground / midnight syncs run with nothing on screen to explain a permission
/// sheet. They must never prompt, and a missing permission must be surfaced to the calendar
/// row rather than silently switching the toggle off.
@MainActor
@Suite("CalendarSyncCoordinator triggers")
struct ServiceCalendarSyncCoordinatorTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makePreferences(_ name: String) -> Preferences {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(suite: defaults)
        preferences.calendarSyncEnabled = true
        return preferences
    }

    @Test("a background sync never asks for access, and leaves the toggle on when it's missing")
    func backgroundSyncDoesNotPromptOrFlipTheToggle() async throws {
        let store = try makeStore()
        let preferences = makePreferences(#function)
        let fake = FakeEventStore()
        let status = CalendarSyncStatus()
        // "Add Events Only", granted on an older build that asked for write access.
        fake.access = .writeOnly

        let outcome = await CalendarSyncCoordinator.sync(
            store: store, preferences: preferences, eventStore: fake, trigger: .background,
            status: status
        )

        #expect(fake.requestAccessCount == 0)
        #expect(outcome == .unauthorized(.writeOnlyAccess))
        #expect(preferences.calendarSyncEnabled)
        #expect(fake.events.isEmpty)
        // …and the calendar row has something to show for it.
        #expect(status.problemMessage?.isEmpty == false)
        #expect(status.lastOutcome == outcome)
    }

    @Test("a background sync with Full Access already granted runs without prompting")
    func backgroundSyncRunsWhenAlreadyAuthorized() async throws {
        let store = try makeStore()
        let preferences = makePreferences(#function)
        let fake = FakeEventStore()
        let status = CalendarSyncStatus()
        fake.access = .full

        let outcome = await CalendarSyncCoordinator.sync(
            store: store, preferences: preferences, eventStore: fake, trigger: .background,
            status: status
        )

        #expect(fake.requestAccessCount == 0)
        #expect(outcome == .synced(events: 0))
        #expect(preferences.calendarSyncEnabled)
        #expect(status.problemMessage == nil)
    }

    @Test("a sync behind the Settings toggle still prompts, and a refusal turns the toggle off")
    func userActionSyncPromptsAndDisablesOnRefusal() async throws {
        let store = try makeStore()
        let preferences = makePreferences(#function)
        let fake = FakeEventStore()
        let status = CalendarSyncStatus()
        fake.access = .denied

        let outcome = await CalendarSyncCoordinator.sync(
            store: store, preferences: preferences, eventStore: fake, trigger: .userAction,
            status: status
        )

        #expect(fake.requestAccessCount == 1)
        #expect(outcome == .denied(.accessDenied))
        #expect(preferences.calendarSyncEnabled == false)
        #expect(status.problemMessage?.isEmpty == false)
    }

    @Test("a later successful sync clears the recorded problem")
    func successClearsTheProblem() async throws {
        let store = try makeStore()
        let preferences = makePreferences(#function)
        let fake = FakeEventStore()
        let status = CalendarSyncStatus()
        fake.access = .denied
        await CalendarSyncCoordinator.sync(
            store: store, preferences: preferences, eventStore: fake, trigger: .background,
            status: status
        )
        #expect(status.problemMessage != nil)

        fake.access = .full
        await CalendarSyncCoordinator.sync(
            store: store, preferences: preferences, eventStore: fake, trigger: .background,
            status: status
        )

        #expect(status.problemMessage == nil)
    }
}
