import GymCore
import SwiftUI

/// The cloud coach, full screen over the Coach tab: one thread's transcript (bubbles, tool
/// chips, draft cards), the input bar, and a toolbar menu for switching, starting and deleting
/// threads. `CoachChatEngine` owns the conversation; this screen owns what it alone knows —
/// which draft cards were applied or discarded, the undo toast, and the error banner.
struct CoachChatView: View {
    /// nil opens the newest thread; a week review opens (or starts) that week's review thread.
    var launch: CoachChatLaunch?

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var engine: CoachChatEngine?
    @State private var threads: [CoachChatThreadSummary] = []
    @State private var input = ""
    @State private var cardStates: [Int: CoachDraftCardState] = [:]
    @State private var undoAction: UndoAction?
    @State private var showingSettings = false
    /// The last text sent, so a "Retry" on a transport failure can send it again.
    @State private var lastSent: String?
    @State private var dismissedError: OpenRouterError.Kind?
    /// A screen-side notice (a draft the store refused), shown in the same banner as errors.
    @State private var notice: CoachChatErrorCopy.Banner?
    /// Long replies the lifter opened out; everything else past the latest turn stays folded.
    @State private var expandedMessageIDs: Set<UUID> = []
    /// "Copied", "Saved to Bench Press notes" or "Remembered" after a long-press action.
    @State private var toast: String?
    /// The lifter's library, read once per open so each bubble can say which exercises it names.
    @State private var library: [SubstitutionCandidate] = []
    /// Draft cards whose "Keep the coach's reasoning" switch the lifter turned off.
    @State private var reasoningOff: Set<Int> = []

    private let archive = CoachChatArchive.standard()
    private let memory = CoachMemoryFile.standard()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                VStack(spacing: 0) {
                    transcript
                    if let notice {
                        CoachChatErrorBanner(
                            banner: notice, onAction: { _ in }, onDismiss: { self.notice = nil }
                        )
                    } else if let error = engine?.lastError, dismissedError != error.kind {
                        CoachChatErrorBanner(
                            banner: CoachChatErrorCopy.banner(for: error),
                            onAction: { act(on: $0) }, onDismiss: { dismissedError = error.kind }
                        )
                    }
                    CoachChatInputBar(
                        text: $input, isStreaming: engine?.isStreaming ?? false, isEnabled: isReady,
                        onSend: send, onStop: { engine?.cancel() }
                    )
                }
            }
            .navigationTitle("Coach")
            .navigationSubtitle(engine.flatMap { CoachUsageText.threadLine($0.usage) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier(A11yID.coachChatClose)
                }
                ToolbarItem(placement: .primaryAction) { threadMenu }
            }
        }
        .dgUndoToast($undoAction)
        .dgNoticeToast($toast)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .task { openLaunch() }
        .onDisappear { engine?.cancel() }
    }

    // MARK: - Transcript

    private var isReady: Bool {
        preferences.coachChatConsentGiven && CoachChatSettings.hasAPIKey && engine != nil
    }

    @ViewBuilder
    private var transcript: some View {
        if !isReady {
            CoachChatSetupState(hasKey: CoachChatSettings.hasAPIKey) { showingSettings = true }
        } else if let engine, engine.messages.isEmpty {
            CoachChatSuggestedPromptsView(onPick: { input = $0; send() })
        } else if let engine {
            ScrollViewReader { proxy in
                ScrollView {
                    let latestTurn = CoachChatTranscript.latestTurnIDs(engine.messages)
                    LazyVStack(alignment: .leading, spacing: DGSpace.s3) {
                        ForEach(CoachChatTranscript.collapse(engine.messages)) { entry in
                            switch entry {
                            case .message(let message):
                                row(message, canFold: !latestTurn.contains(message.id))
                            case .toolGroup(let label, let count, let failed):
                                CoachToolChip(label: label, failed: failed, count: count)
                            }
                        }
                        if engine.isStreaming, CoachChatTranscript.isWaitingForText(engine.messages) {
                            CoachThinkingRow()
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s3)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: engine.messages.count) { _, _ in
                    withAnimation(DGMotion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .accessibilityIdentifier(A11yID.coachChatTranscript)
            }
        }
    }

    @ViewBuilder
    private func row(_ message: CoachChatMessage, canFold: Bool) -> some View {
        if message.role == .draft, let index = message.draftIndex, let draft = engine?.drafts[safe: index] {
            let reviews = engine?.reviews ?? []
            let drafter = preferences.coachModelID
            CoachDraftCard(
                draft: draft, state: cardStates[index] ?? .proposed, formatWeight: preferences.formatWeight,
                originLabel: reviews.isEmpty
                    ? nil : CoachReviewCopy.originLabel(for: index, in: reviews, drafterModelID: drafter),
                reviewStrip: CoachDraftLinks.review(for: index, in: reviews).map(CoachReviewCopy.strip),
                rationale: CoachDraftLinks.rationale(for: index, in: reviews),
                onApply: { apply(draft, at: index) }, onDiscard: { discard(at: index) },
                onCopy: {
                    copy(CoachDraftDetail.copyText(for: draft, formatWeight: preferences.formatWeight))
                },
                saveTargets: CoachChatSaveTargets.forDraft(draft), onSave: save,
                keepsReasoning: draft.createsRoutine ? keepsReasoningBinding(for: index) : nil
            )
        } else {
            CoachChatMessageRow(
                message: message, review: review(for: message), canFold: canFold,
                isExpanded: isExpandedBinding(for: message.id),
                onCopy: { copy(CoachMarkdown.plainText(message.text)) },
                saveTargets: CoachChatSaveTargets.forReply(message.text, library: library), onSave: save
            )
        }
    }

    private func keepsReasoningBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { !reasoningOff.contains(index) },
            set: { if $0 { reasoningOff.remove(index) } else { reasoningOff.insert(index) } }
        )
    }

    private func isExpandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedMessageIDs.contains(id) },
            set: { if $0 { expandedMessageIDs.insert(id) } else { expandedMessageIDs.remove(id) } }
        )
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        Haptics.confirm()
        toast = "Copied"
    }

    private func save(_ target: CoachChatSaveTarget) {
        let threadID = engine?.threadID
        guard CoachChatSaver.save(target, store: store, memory: memory, threadID: threadID) else { return }
        Haptics.confirm()
        toast = target.toast
    }

    private func review(for message: CoachChatMessage) -> CoachChatReview? {
        message.reviewIndex.flatMap { engine?.reviews[safe: $0] }
    }

    // MARK: - Threads

    private var threadMenu: some View {
        CoachChatThreadMenu(
            threads: threads, currentID: engine?.threadID, canDelete: engine?.messages.isEmpty == false,
            onNew: { open(thread: nil) }, onOpen: { open(thread: archive?.load(id: $0)) },
            onDelete: deleteCurrent
        )
    }

    /// Opens what the screen was launched for: the newest saved thread (or a fresh one), or the
    /// week's review thread — started with the canned turn when it does not exist yet.
    private func openLaunch() {
        threads = archive?.list() ?? []
        switch launch {
        case nil:
            open(thread: threads.first.flatMap { archive?.load(id: $0.id) })
        case .weekReview(let weekEnding, let threadID):
            open(thread: threadID.flatMap { archive?.load(id: $0) })
            guard threadID == nil, isReady, let engine else { return }
            let calendar = preferences.trainingCalendar
            preferences.coachWeekReviewLastKey = CoachWeekReview.weekKey(now: weekEnding, calendar: calendar)
            lastSent = CoachWeekReviewPrompt.userTurn(weekEnding: weekEnding, calendar: calendar)
            Task {
                await engine.startWeekReview(weekEnding: weekEnding, calendar: calendar)
                threads = archive?.list() ?? []
            }
        }
    }

    private func open(thread: CoachChatThread?) {
        engine?.cancel()
        engine = CoachChatEngineFactory.make(thread: thread, store: store, preferences: preferences)
        library = store.substitutionCandidates()
        cardStates = [:]
        reasoningOff = []
        expandedMessageIDs = []
        dismissedError = nil
        lastSent = nil
    }

    private func deleteCurrent() {
        guard let engine else { return }
        engine.cancel()
        try? archive?.delete(id: engine.threadID)
        threads.removeAll { $0.id == engine.threadID }
        open(thread: nil)
    }

    // MARK: - Actions

    private func send() {
        guard let engine else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        lastSent = text
        dismissedError = nil
        Task {
            await engine.send(text)
            threads = archive?.list() ?? []
        }
    }

    private func act(on action: CoachChatErrorCopy.Action) {
        switch action {
        case .openSettings:
            showingSettings = true
        case .openOpenRouter:
            if let url = CoachChatErrorCopy.openRouterCreditsURL { openURL(url) }
        case .retry:
            guard let lastSent, let engine, !engine.isStreaming else { return }
            dismissedError = nil
            Task { await engine.send(lastSent) }
        }
    }

    /// Applies through the store and offers Undo, like Approve on the rule cards. A refusal
    /// (the routine it targets is gone) leaves the card proposed and says so in the toast.
    /// The card's linked pair (the drafter's or the reviewer's version of the same proposal)
    /// settles as "Not chosen"; Undo brings both back. A routine or program card with "Keep
    /// the coach's reasoning" on carries the reply that came with it into the routine note.
    private func apply(_ draft: CoachChatDraft, at index: Int) {
        let reasoning = draft.createsRoutine && !reasoningOff.contains(index)
            ? CoachChatTranscript.reasoning(forDraftAt: index, in: engine?.messages ?? []) : nil
        guard let application = CoachChatEngineFactory.apply(draft, reasoning: reasoning, store: store) else {
            notice = CoachChatErrorCopy.applyRefused
            return
        }
        notice = nil
        let linked = CoachDraftLinks.linkedDraftIndex(for: index, in: engine?.reviews ?? [])
        cardStates = CoachDraftLinks.applied(at: index, linked: linked, states: cardStates)
        undoAction = UndoAction(message: "Applied: \(draft.summary)") {
            CoachChatEngineFactory.undo(application, store: store)
            cardStates = CoachDraftLinks.reverted(at: index, linked: linked, states: cardStates)
        }
    }

    private func discard(at index: Int) {
        cardStates[index] = .discarded
        undoAction = UndoAction(message: "Discarded proposal") { cardStates[index] = .proposed }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    if let store = PreviewStore.make() {
        CoachChatView()
            .environment(store)
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
