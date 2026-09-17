import GymCore
import SwiftUI

/// What the chat screen does off its body: opening and switching threads, sending, the
/// week review, and applying or discarding a draft card. Split from the view so each file
/// stays readable; the state lives on `CoachChatScreen`.
extension CoachChatScreen {
    // MARK: - Threads

    var threadMenu: some View {
        CoachChatThreadMenu(
            threads: threads, currentID: engine?.threadID, canDelete: engine?.messages.isEmpty == false,
            onNew: { open(thread: nil) }, onOpen: { open(thread: archive?.load(id: $0)) },
            onDelete: deleteCurrent
        )
    }

    /// Opens what the screen was launched for: the newest saved thread (or a fresh one), or the
    /// week's review thread — started with the canned turn when it does not exist yet.
    func openLaunch() {
        refreshHeader()
        threads = archive?.list() ?? []
        switch launch {
        case nil:
            open(thread: threads.first.flatMap { archive?.load(id: $0.id) })
        case .weekReview(let weekEnding, let threadID):
            open(thread: threadID.flatMap { archive?.load(id: $0) })
            guard threadID == nil else { return }
            beginWeekReview(weekEnding: weekEnding)
        }
    }

    func open(thread: CoachChatThread?) {
        engine?.cancel()
        engine = CoachChatEngineFactory.make(thread: thread, store: store, preferences: preferences)
        library = store.substitutionCandidates()
        saveTargetCache.reset()
        cardStates = [:]
        reasoningOff = []
        expandedMessageIDs = []
        dismissedError = nil
        lastSent = nil
    }

    func deleteCurrent() {
        guard let engine else { return }
        engine.cancel()
        try? archive?.delete(id: engine.threadID)
        threads.removeAll { $0.id == engine.threadID }
        open(thread: nil)
    }

    // MARK: - Week review

    /// Starts the week's review on a fresh thread (the open one is kept if it is still empty)
    /// and records the week as reviewed, exactly as Home's card used to do before handing off.
    func beginWeekReview(weekEnding: Date) {
        guard isReady else { return }
        if engine?.messages.isEmpty == false { open(thread: nil) }
        guard let engine else { return }
        let calendar = preferences.trainingCalendar
        preferences.coachWeekReviewLastKey = CoachWeekReview.weekKey(now: weekEnding, calendar: calendar)
        lastSent = CoachWeekReviewPrompt.userTurn(weekEnding: weekEnding, calendar: calendar)
        dismissedError = nil
        Task {
            await engine.startWeekReview(weekEnding: weekEnding, calendar: calendar)
            threads = archive?.list() ?? []
            refreshHeader()
        }
    }

    // MARK: - Actions

    /// A chip: "Review my week" starts the review; every other prompt is sent as typed.
    func pick(_ chip: String) {
        if chip == CoachChatOpening.reviewChip, let weekReview {
            beginWeekReview(weekEnding: weekReview.weekEnding)
        } else {
            input = chip
            send()
        }
    }

    func send() {
        guard let engine else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        lastSent = text
        dismissedError = nil
        Task {
            await engine.send(text)
            threads = archive?.list() ?? []
            refreshHeader()
        }
    }

    func act(on action: CoachChatErrorCopy.Action) {
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

    func copy(_ text: String) {
        UIPasteboard.general.string = text
        Haptics.confirm()
        toast = "Copied"
    }

    func save(_ target: CoachChatSaveTarget) {
        let threadID = engine?.threadID
        guard CoachChatSaver.save(target, store: store, memory: memory, threadID: threadID) else { return }
        Haptics.confirm()
        toast = target.toast
    }

    /// Applies through the store and offers Undo, like Approve on the rule cards. A refusal
    /// (the routine it targets is gone) leaves the card proposed and says so in the toast.
    /// The card's linked pair (the drafter's or the reviewer's version of the same proposal)
    /// settles as "Not chosen"; Undo brings both back. A routine or program card with "Keep
    /// the coach's reasoning" on carries the reply that came with it into the routine note.
    func apply(_ draft: CoachChatDraft, at index: Int) {
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

    func discard(at index: Int) {
        cardStates[index] = .discarded
        undoAction = UndoAction(message: "Discarded proposal") { cardStates[index] = .proposed }
    }
}
