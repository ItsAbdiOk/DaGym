import GymCore
import SwiftUI

/// The cloud coach as the redesign draws it: one thread's transcript (bubbles, the tool trail,
/// draft cards), the prompt chips and the input pill, under a "Coach" title whose subtitle says
/// whether a weekly review is waiting and what the coach has cost. Pushed from the You hub
/// (`YouDestination.coach`), or wrapped in `CoachChatView` for the full-screen covers that
/// Home and Train still open. `CoachChatEngine` owns the conversation; this screen owns what
/// it alone knows — which draft cards were applied or discarded, the undo toast, the banner.
struct CoachChatScreen: View {
    /// nil opens the newest thread; a week review opens (or starts) that week's review thread.
    var launch: CoachChatLaunch?
    /// True inside a full-screen cover: adds Close, since there is no system back button.
    var isPresentedModally = false

    @Environment(WorkoutStore.self) var store
    @Environment(Preferences.self) var preferences
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @State var engine: CoachChatEngine?
    @State var threads: [CoachChatThreadSummary] = []
    @State var input = ""
    @State var cardStates: [Int: CoachDraftCardState] = [:]
    @State var undoAction: UndoAction?
    @State var showingSettings = false
    /// The last text sent, so a "Retry" on a transport failure can send it again.
    @State var lastSent: String?
    @State var dismissedError: OpenRouterError.Kind?
    /// A screen-side notice (a draft the store refused), shown in the same banner as errors.
    @State var notice: CoachChatErrorCopy.Banner?
    /// Long replies the lifter opened out; everything else past the latest turn stays folded.
    @State var expandedMessageIDs: Set<UUID> = []
    /// "Copied", "Saved to Bench Press notes" or "Remembered" after a long-press action.
    @State var toast: String?
    /// The lifter's library, read once per open so each bubble can say which exercises it names.
    @State var library: [SubstitutionCandidate] = []
    /// Each bubble's save targets, scanned when its menu first opens and kept while its text holds.
    @State var saveTargetCache = CoachChatSaveTargetCache()
    /// Draft cards whose "Keep the coach's reasoning" switch the lifter turned off.
    @State var reasoningOff: Set<Int> = []
    /// The week under review and whether a review is due — the subtitle, the opening bubble
    /// and the "Review my week" chip all read it.
    @State var weekReview: WeekReviewState?
    @State var recap: WeeklyRecap?
    @State var ledger = CoachChatUsageLedger()
    /// Re-read on every appearance so a key saved in Settings flips the setup state.
    @State var hasKey = CoachChatSettings.hasAPIKey
    @FocusState var inputFocused: Bool

    let archive = CoachChatArchive.standard()
    let memory = CoachMemoryFile.standard()

    var body: some View {
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
                    chips: CoachChatOpening.chips(reviewDue: reviewDue), focus: $inputFocused,
                    onChip: pick, onSend: send, onStop: { engine?.cancel() }
                )
            }
        }
        .navigationTitle("Coach")
        .toolbar(.hidden, for: .tabBar)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresentedModally {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier(A11yID.coachChatClose)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Insights") { InsightsScreen() }
                    .accessibilityIdentifier(A11yID.youInsights)
            }
            ToolbarItem(placement: .topBarTrailing) { threadMenu }
        }
        .dgUndoToast($undoAction)
        .dgNoticeToast($toast)
        .sheet(isPresented: $showingSettings, onDismiss: refreshHeader) { SettingsView(standalone: true) }
        .task { openLaunch() }
        .refreshOnStoreChange(refreshHeader)
        .onDisappear { engine?.cancel() }
    }

    // MARK: - Header

    var isReady: Bool {
        preferences.coachChatConsentGiven && hasKey && engine != nil
    }

    var reviewDue: Bool { weekReview?.status.isDue ?? false }

    /// The thread's own tokens once it has used any (the old header line), else the month's
    /// spend — a thread that cost nothing yet still tells the lifter what the coach has cost.
    private var subtitle: String {
        if let engine, let line = CoachUsageText.threadLine(engine.usage) {
            return reviewDue ? "Weekly review · \(line)" : line
        }
        return CoachChatOpening.subtitle(
            reviewDue: reviewDue, ledger: ledger, now: Date(), calendar: preferences.trainingCalendar
        )
    }

    /// Re-reads what the header and the opening bubble show: the week's status, the recap and
    /// the ledger. Cheap (the archive's index, one recap), so it runs on every store change.
    func refreshHeader() {
        hasKey = CoachChatSettings.hasAPIKey
        let calendar = preferences.trainingCalendar
        weekReview = WeekReviewState.make(
            store: store, preferences: preferences, archive: archive,
            isConfigured: preferences.coachChatConsentGiven && hasKey
        )
        recap = store.weeklyRecap(for: Date(), weeklyGoal: preferences.weeklyGoal, calendar: calendar)
        ledger = CoachChatUsageLedgerStore.standard.load()
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        if !isReady {
            CoachChatSetupState(hasKey: hasKey) { showingSettings = true }
        } else if let engine, engine.messages.isEmpty {
            ScrollView {
                CoachChatOpeningBubble(text: openingLine) { inputFocused = true }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s4)
            }
            .scrollDismissesKeyboard(.interactively)
        } else if let engine {
            ScrollViewReader { proxy in
                ScrollView {
                    let latestTurn = CoachChatTranscript.latestTurnIDs(engine.messages)
                    let blocks = CoachChatTranscript.blocks(engine.messages)
                    let thinking = engine.isStreaming && CoachChatTranscript.isWaitingForText(engine.messages)
                    LazyVStack(alignment: .leading, spacing: DGSpace.s3) {
                        ForEach(blocks) { block in
                            switch block {
                            case .message(let message):
                                row(message, canFold: !latestTurn.contains(message.id))
                            case .trail(let lines):
                                CoachToolTrailBubble(
                                    lines: lines, isThinking: thinking && block.id == blocks.last?.id
                                )
                            }
                        }
                        if thinking, !isTrail(blocks.last) {
                            CoachToolTrailBubble(lines: [], isThinking: true)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.vertical, DGSpace.s4)
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

    private func isTrail(_ block: CoachChatTranscript.Block?) -> Bool {
        if case .trail? = block { return true }
        return false
    }

    private var openingLine: String {
        guard let recap else { return "Ask me anything about your training." }
        let volume = "\(preferences.formatVolume(kg: recap.volumeKg)) \(preferences.unitSymbol)"
        return CoachChatOpening.line(recap: recap, reviewDue: reviewDue, volume: volume)
    }

    @ViewBuilder
    private func row(_ message: CoachChatMessage, canFold: Bool) -> some View {
        if message.role == .draft, let index = message.draftIndex, let draft = draft(at: index) {
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
                saveTargets: { saveTargetCache.targets(for: message, library: library) }, onSave: save
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

    private func review(for message: CoachChatMessage) -> CoachChatReview? {
        guard let index = message.reviewIndex, let reviews = engine?.reviews,
              reviews.indices.contains(index) else { return nil }
        return reviews[index]
    }

    private func draft(at index: Int) -> CoachChatDraft? {
        guard let drafts = engine?.drafts, drafts.indices.contains(index) else { return nil }
        return drafts[index]
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack { CoachChatScreen() }
            .environment(store)
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
