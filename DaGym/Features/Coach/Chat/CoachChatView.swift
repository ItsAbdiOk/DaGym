import GymCore
import SwiftUI

/// The cloud coach, full screen over the Coach tab: one thread's transcript (bubbles, tool
/// chips, draft cards), the input bar, and a toolbar menu for switching, starting and deleting
/// threads. `CoachChatEngine` owns the conversation; this screen owns what it alone knows —
/// which draft cards were applied or discarded, the undo toast, and the error banner.
struct CoachChatView: View {
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

    private let archive = CoachChatArchive.standard()

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier(A11yID.coachChatClose)
                }
                ToolbarItem(placement: .primaryAction) { threadMenu }
            }
        }
        .dgUndoToast($undoAction)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .task { openNewest() }
        .onDisappear { engine?.cancel() }
    }

    // MARK: - Transcript

    private var isReady: Bool {
        preferences.coachChatConsentGiven && CoachChatSettings.hasAPIKey && engine != nil
    }

    @ViewBuilder
    private var transcript: some View {
        if !isReady {
            setupState
        } else if let engine, engine.messages.isEmpty {
            suggestedPrompts
        } else if let engine {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DGSpace.s3) {
                        ForEach(CoachChatTranscript.collapse(engine.messages)) { entry in
                            switch entry {
                            case .message(let message): row(message)
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
    private func row(_ message: CoachChatMessage) -> some View {
        if message.role == .draft, let index = message.draftIndex, let draft = engine?.drafts[safe: index] {
            CoachDraftCard(
                draft: draft, state: cardStates[index] ?? .proposed, formatWeight: preferences.formatWeight,
                onApply: { apply(draft, at: index) }, onDiscard: { discard(at: index) }
            )
        } else {
            CoachChatMessageRow(message: message)
        }
    }

    private var setupState: some View {
        VStack {
            Spacer()
            EmptyState(
                symbol: "key",
                title: "Set Up Your Coach",
                message: CoachChatSettings.hasAPIKey
                    ? "Agree to what's sent in Settings before the coach can read your training."
                    : "Add your OpenRouter API key in Settings. Your key stays in the Keychain and "
                        + "nothing is sent until you ask a question.",
                action: "Open Settings", onAction: { showingSettings = true }
            )
            .padding(.horizontal, DGSpace.s6)
            Spacer()
        }
    }

    private var suggestedPrompts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                Text("Try asking").dgLabel()
                ForEach(CoachChatSuggestedPrompts.all, id: \.self) { prompt in
                    Button {
                        input = prompt
                        send()
                    } label: {
                        HStack {
                            Text(prompt)
                                .font(DGFont.body)
                                .foregroundStyle(DGColor.ink1)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DGSpace.s2)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DGColor.aiVioletText)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dgCard(padding: DGSpace.s4)
                    }
                    .buttonStyle(.dgControl)
                    .accessibilityIdentifier(A11yID.coachChatSuggestedPrompt)
                }
                Text("The coach reads your log through tools and cites what it used. Proposals arrive as "
                    + "cards you apply or discard — nothing changes until you tap Apply.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DGSpace.s2)
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s5)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Threads

    private var threadMenu: some View {
        Menu {
            Button { open(thread: nil) } label: { Label("New chat", systemImage: "plus") }
            if !threads.isEmpty {
                Section("Recent") {
                    ForEach(threads.prefix(10)) { summary in
                        Button {
                            open(thread: archive?.load(id: summary.id))
                        } label: {
                            if summary.id == engine?.threadID {
                                Label(summary.title, systemImage: "checkmark")
                            } else {
                                Text(summary.title)
                            }
                        }
                    }
                }
            }
            if let engine, !engine.messages.isEmpty {
                Button(role: .destructive, action: deleteCurrent) {
                    Label("Delete this chat", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Chats")
        }
        .accessibilityIdentifier(A11yID.coachChatThreadMenu)
    }

    /// Opens the newest saved thread, or a fresh one when there is none.
    private func openNewest() {
        threads = archive?.list() ?? []
        let newest = threads.first.flatMap { archive?.load(id: $0.id) }
        open(thread: newest)
    }

    private func open(thread: CoachChatThread?) {
        engine?.cancel()
        engine = CoachChatEngineFactory.make(thread: thread, store: store, preferences: preferences)
        cardStates = [:]
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
    private func apply(_ draft: CoachChatDraft, at index: Int) {
        guard let application = CoachChatEngineFactory.apply(draft, store: store) else {
            notice = CoachChatErrorCopy.applyRefused
            return
        }
        notice = nil
        cardStates[index] = .applied
        undoAction = UndoAction(message: "Applied: \(draft.summary)") {
            CoachChatEngineFactory.undo(application, store: store)
            cardStates[index] = .proposed
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
