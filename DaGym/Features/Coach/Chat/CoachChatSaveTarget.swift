import Foundation
import GymCore

/// Where a long-pressed reply or card can be kept, beyond the clipboard: as an "always" note
/// on an exercise it names (shown on that exercise's card in future workouts), or as a coach
/// memory fact (Settings → Coach memory, and the next system prompt). Each is offered only
/// when it applies; the screen performs the save and shows `toast`. The routine note is not
/// here — it is part of Apply on a routine or program card.
enum CoachChatSaveTarget: Identifiable, Hashable {
    case exerciseNote(exerciseID: UUID, exerciseName: String, note: String)
    case remember(gist: String)

    var id: String {
        switch self {
        case .exerciseNote(let exerciseID, _, _): "note:\(exerciseID.uuidString)"
        case .remember: "remember"
        }
    }

    var menuLabel: String {
        switch self {
        case .exerciseNote(_, let name, _): "Save as note for \(name)"
        case .remember: "Remember this"
        }
    }

    var symbol: String {
        switch self {
        case .exerciseNote: "note.text.badge.plus"
        case .remember: "brain"
        }
    }

    /// What VoiceOver reads: the label plus where the text ends up.
    var accessibilityLabel: String {
        switch self {
        case .exerciseNote(_, let name, _): "Save as note for \(name), shown on its card in every workout"
        case .remember: "Remember this in coach memory"
        }
    }

    /// The confirmation after the save.
    var toast: String {
        switch self {
        case .exerciseNote(_, let name, _): "Saved to \(name) notes"
        case .remember: "Remembered"
        }
    }
}

enum CoachChatSaveTargets {
    /// The targets for the coach's words: a note for each library exercise the reply names
    /// (in order of mention, a short picker when there are several), then "Remember this".
    /// Nothing for an empty reply.
    static func forReply(_ markdown: String, library: [SubstitutionCandidate]) -> [CoachChatSaveTarget] {
        let text = CoachMarkdown.plainText(markdown)
        guard let note = CoachChatSaveText.exerciseNote(text) else { return [] }
        var targets = CoachChatSaveText.exercisesNamed(in: text, library: library).map { exercise in
            CoachChatSaveTarget.exerciseNote(exerciseID: exercise.id, exerciseName: exercise.name, note: note)
        }
        if let gist = CoachChatSaveText.memoryGist(text) {
            targets.append(.remember(gist: gist))
        }
        return targets
    }

    /// The targets for a draft card: on a routine or program, a note for each exercise the
    /// drafter gave a reason (the reason is the note); on a deload or swap, the exercise it
    /// changes with the card's summary. Schedules name no exercise.
    static func forDraft(_ draft: CoachChatDraft) -> [CoachChatSaveTarget] {
        switch draft {
        case .routine(let proposal):
            return reasonTargets(proposal.exercises)
        case .program(let proposal):
            return reasonTargets(proposal.routines.flatMap(\.exercises))
        case .deload(let proposal):
            guard let id = proposal.exerciseID, let name = proposal.exerciseName,
                  let note = CoachChatSaveText.exerciseNote(draft.summary) else { return [] }
            return [.exerciseNote(exerciseID: id, exerciseName: name, note: note)]
        case .swap(let proposal):
            guard let id = proposal.toExerciseID, let name = proposal.toExerciseName,
                  let note = CoachChatSaveText.exerciseNote(draft.summary) else { return [] }
            return [.exerciseNote(exerciseID: id, exerciseName: name, note: note)]
        case .schedule:
            return []
        }
    }

    private static func reasonTargets(_ specs: [CoachChatExerciseSpec]) -> [CoachChatSaveTarget] {
        var seen: Set<UUID> = []
        return specs.compactMap { spec in
            guard let id = spec.exerciseID, let name = spec.exerciseName, let reason = spec.reason,
                  let note = CoachChatSaveText.exerciseNote(reason), seen.insert(id).inserted
            else { return nil }
            return .exerciseNote(exerciseID: id, exerciseName: name, note: note)
        }
    }
}

/// `forReply` per bubble, worked out the first time its context menu opens and reused until the
/// message's text changes (a reply still streaming), so the library scan never runs on render.
/// A plain class rather than `@Observable`: filling it from inside a menu must not invalidate
/// the screen. One per open thread; `reset` when the library it scans is re-read.
@MainActor
final class CoachChatSaveTargetCache {
    private struct Entry {
        var textHash: Int
        var targets: [CoachChatSaveTarget]
    }

    private var entries: [UUID: Entry] = [:]
    /// Test hook: how many scans have run.
    private(set) var scanCount = 0

    func targets(for message: CoachChatMessage, library: [SubstitutionCandidate]) -> [CoachChatSaveTarget] {
        let textHash = message.text.hashValue
        if let entry = entries[message.id], entry.textHash == textHash { return entry.targets }
        let targets = CoachChatSaveTargets.forReply(message.text, library: library)
        entries[message.id] = Entry(textHash: textHash, targets: targets)
        scanCount += 1
        return targets
    }

    func reset() {
        entries.removeAll()
    }
}

/// Keeps the words where the menu item said: an "always" note on the exercise (a repeat save
/// of the same text is one note), or a coach memory fact filed under Other with the thread as
/// its source. False when nothing was kept (no memory file, or the write failed).
@MainActor
enum CoachChatSaver {
    @discardableResult
    static func save(
        _ target: CoachChatSaveTarget, store: WorkoutStore, memory: CoachMemoryFile?, threadID: UUID?,
        now: Date = Date()
    ) -> Bool {
        switch target {
        case .exerciseNote(let exerciseID, _, let note):
            return store.addCoachExerciseNote(exerciseID: exerciseID, text: note, createdAt: now) != nil
        case .remember(let gist):
            let fact = CoachMemoryFact(text: gist, topic: .other, createdAt: now, sourceThreadID: threadID)
            return (try? memory?.remember(fact)) != nil
        }
    }
}

extension CoachChatDraft {
    /// Whether Apply saves a routine the reasoning can live on.
    var createsRoutine: Bool {
        switch self {
        case .routine, .program: true
        case .schedule, .deload, .swap: false
        }
    }
}

extension CoachChatTranscript {
    /// The coach's words that go with the draft card at `index` — the reply that followed the
    /// card in the same turn, else the text that led into it. What Apply keeps as the routine
    /// note when "Keep the coach's reasoning" is on. nil when the turn had no words.
    static func reasoning(forDraftAt draftIndex: Int, in messages: [CoachChatMessage]) -> String? {
        guard let position = messages.firstIndex(where: { $0.role == .draft && $0.draftIndex == draftIndex })
        else { return nil }
        let turnStart = messages[..<position].lastIndex { $0.role == .user } ?? messages.startIndex
        let turnEnd = messages[position...].firstIndex { $0.role == .user } ?? messages.endIndex
        let after = messages[position..<turnEnd].first(where: isReasoning)
        let before = messages[turnStart..<position].last(where: isReasoning)
        return (after ?? before).map { CoachMarkdown.plainText($0.text) }
    }

    private static func isReasoning(_ message: CoachChatMessage) -> Bool {
        message.role == .assistant && message.isNote != true
            && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
