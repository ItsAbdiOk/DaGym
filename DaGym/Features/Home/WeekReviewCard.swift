import GymCore
import SwiftUI

/// What Home's week-review card knows: the week under review, whether a check-in is due, and
/// the thread's headline once the coach has replied. Pure over `(store, preferences, archive,
/// now)` like `HomeSnapshot`, with the chat's readiness injected so a test needs no Keychain.
/// Reads the archive's index only, never a transcript: Home refreshes on every store change.
struct WeekReviewState: Equatable {
    var weekEnding: Date
    var status: CoachWeekReview.Status
    /// The review thread's id when one exists, so the chat opens straight onto it.
    var threadID: UUID?
    /// The first line of the coach's reply; nil until it has answered.
    var headline: String?

    var isVisible: Bool { status.isVisible }

    @MainActor
    static func make(
        store: WorkoutStore, preferences: Preferences, archive: CoachChatArchive?,
        isConfigured: Bool, now: Date = Date()
    ) -> WeekReviewState {
        let calendar = preferences.trainingCalendar
        let weekEnding = CoachWeekReview.weekEnding(now: now, calendar: calendar)
        let weekKey = DateKey.string(for: weekEnding, calendar: calendar)
        let thread = isConfigured ? archive?.weekReview(weekKey: weekKey) : nil
        let count = CoachWeekReview.workoutCount(
            dates: store.workoutDates(), weekEnding: weekEnding, calendar: calendar
        )
        let status = CoachWeekReview.Status(
            weekKey: weekKey, workoutCount: count, isConfigured: isConfigured, hasThread: thread != nil,
            dismissedWeekKey: preferences.coachWeekReviewDismissedKey,
            lastReviewedWeekKey: preferences.coachWeekReviewLastKey
        )
        return WeekReviewState(
            weekEnding: weekEnding, status: status, threadID: thread?.id,
            headline: thread?.firstReply.flatMap { CoachWeekReviewPrompt.headline(from: $0) }
        )
    }
}

/// The Sunday check-in on Home. "Week review ready" offers the review; tapping opens the coach
/// chat on a fresh review thread and sends the canned turn. Once the coach has replied the card
/// shows its first line and "Open". "Not this week" hides it until the next Sunday. Violet,
/// like everything on Home that sends data off the phone.
struct WeekReviewCard: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var state: WeekReviewState?
    @State private var launch: CoachChatLaunch?

    private let archive = CoachChatArchive.standard()

    var body: some View {
        Group {
            if let state, state.isVisible {
                card(state)
            }
        }
        .task { refresh() }
        .refreshOnStoreChange(refresh)
        .onChange(of: preferences.coachChatConsentGiven) { refresh() }
        .fullScreenCover(item: $launch, onDismiss: refresh) { launch in
            CoachChatView(launch: launch)
        }
    }

    private func card(_ state: WeekReviewState) -> some View {
        WhyCard(
            title: state.headline == nil ? "Week review" : "Week review · done",
            message: message(state),
            primary: state.threadID == nil ? "Review my week" : "Open",
            secondary: state.threadID == nil ? "Not this week" : "Hide",
            onPrimary: { open(state) },
            onSecondary: dismiss
        )
        .accessibilityIdentifier(A11yID.homeWeekReview)
    }

    private func message(_ state: WeekReviewState) -> String {
        if let headline = state.headline { return headline }
        if state.threadID != nil { return "The coach is still working on this week's review." }
        let sessions = state.status.workoutCount == 1 ? "1 session" : "\(state.status.workoutCount) sessions"
        return "Week review ready: \(sessions) logged. The coach reads the week, says what moved and "
            + "what stalled, and proposes one tweak you can apply with a tap."
    }

    private func refresh() {
        state = WeekReviewState.make(
            store: store, preferences: preferences, archive: archive,
            isConfigured: preferences.coachChatConsentGiven && CoachChatSettings.hasAPIKey
        )
    }

    /// The chat records `coachWeekReviewLastKey` itself, once the review is actually sent.
    private func open(_ state: WeekReviewState) {
        launch = .weekReview(weekEnding: state.weekEnding, threadID: state.threadID)
    }

    private func dismiss() {
        preferences.coachWeekReviewDismissedKey = state?.status.weekKey
        refresh()
    }
}

/// How the coach chat was opened: on the newest thread, or on a week review to start or resume.
enum CoachChatLaunch: Identifiable, Equatable {
    case weekReview(weekEnding: Date, threadID: UUID?)

    var id: String {
        switch self {
        case .weekReview(let weekEnding, _): "weekReview:\(weekEnding.timeIntervalSince1970)"
        }
    }
}
