import AppIntents
import Observation

/// The single inbox every `openAppWhenRun` App Intent drops its request into, and the thing
/// `RootView` observes. It is `@Observable` on purpose: these used to be plain static `Bool`s
/// that only `RootView.refresh()` polled, so on a warm launch — where the intent's `perform()`
/// can land *after* the scene-phase refresh has already run — the tap did nothing until some
/// unrelated refresh happened to come along. A published array means the view reacts to the
/// request itself instead of to whatever happens next.
///
/// Requests are still only *acted on* once today's routine has been fetched: a request that
/// arrives before then stays queued (`routineLoaded: false`) rather than being burned against
/// `routine == nil`, so the hand-off survives a cold launch too.
@Observable
@MainActor
final class PendingIntentHandoff {
    enum Action: Equatable, CaseIterable {
        /// Ordered by how they must run: the rest timer starts today's routine itself if it has
        /// to, so it goes before the plain "start workout".
        case startRestTimer
        case startWorkout
        case showGymCard
    }

    static let shared = PendingIntentHandoff()

    /// What has been requested and not yet acted on. Reading this from a view body is what makes
    /// `RootView` re-evaluate the moment an intent lands.
    private(set) var pending: [Action] = []

    func request(_ action: Action) {
        guard !pending.contains(action) else { return }
        pending.append(action)
    }

    /// Removes and returns `action` if it was pending.
    func consume(_ action: Action) -> Bool {
        guard let index = pending.firstIndex(of: action) else { return false }
        pending.remove(at: index)
        return true
    }

    /// The actions to run now, clearing them; empty (and untouched) until `routineLoaded`.
    static func consume(routineLoaded: Bool) -> [Action] {
        guard routineLoaded else { return [] }
        let inbox = shared
        return Action.allCases.filter { inbox.consume($0) }
    }
}

/// Set by `StartRestTimerIntent.perform()` (running in the app's process once it opens),
/// consumed by `RootView` on appear. This is the one-line hookup a Control Center button needs:
/// unlike the Live Activity intents in `RestIntents.swift`, this one has no running session to
/// call into yet, so it can't use an in-process closure — it has to wait for the app to open.
@MainActor
enum PendingIntentAction {
    static func requestStartRestTimer() {
        PendingIntentHandoff.shared.request(.startRestTimer)
    }

    /// Returns whether a rest timer was requested, clearing it so it only fires once.
    static func consumeStartRestTimer() -> Bool {
        PendingIntentHandoff.shared.consume(.startRestTimer)
    }
}

/// Control Center "Rest timer" button (`RestTimerControl`, iOS 18+ `ControlWidget`). Opens the
/// app and starts a default-length rest — see `RootView.startPendingRestTimerIfNeeded()`.
struct StartRestTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Rest Timer"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingIntentAction.requestStartRestTimer()
        return .result()
    }
}
