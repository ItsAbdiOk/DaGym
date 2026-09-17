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

/// The Sunday check-in on Home. "Your week is ready to review" offers the review; tapping the
/// row opens the coach chat on a fresh review thread and sends the canned turn. Once the coach
/// has replied the row shows its first line and opens the thread. "Not this week" / "Hide"
/// live in the row's context menu (and as a VoiceOver action) and hide it until next Sunday.
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
        let dismissTitle = state.threadID == nil ? "Not this week" : "Hide"
        return Button { open(state) } label: {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(width: 34, height: 34)
                    .background(DGColor.coral, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(state))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                        .lineLimit(2)
                    Text(message(state))
                        .font(.system(size: 12.5))
                        .foregroundStyle(DGColor.ink3)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HomeChevron()
            }
            .dgCard(radius: 20, padding: DGSpace.s4)
        }
        .buttonStyle(DGPressStyle())
        .contextMenu { Button(dismissTitle, systemImage: "eye.slash", action: dismiss) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: dismissTitle, dismiss)
        .accessibilityIdentifier(A11yID.homeWeekReview)
    }

    private func title(_ state: WeekReviewState) -> String {
        if let headline = state.headline { return headline }
        return state.threadID == nil ? "Your week is ready to review" : "Week review in progress"
    }

    private func message(_ state: WeekReviewState) -> String {
        if state.headline != nil { return "Week review · open the thread" }
        if state.threadID != nil { return "The coach is still working on this week's review." }
        let sessions = state.status.workoutCount == 1 ? "1 session" : "\(state.status.workoutCount) sessions"
        return "Sunday check-in from your coach · \(sessions) logged"
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
