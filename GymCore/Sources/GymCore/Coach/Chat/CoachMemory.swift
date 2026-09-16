import Foundation

/// One thing the coach has been told to keep in mind across chats — "knees hurt on leg
/// press", "trains Tuesday and Thursday only", "no cable stack at home". Never a weight, set or
/// rep: those live in the log and the tools read them. Local to the phone; the app keeps
/// these in a JSON file beside the chat archive, never in the synced store.
public struct CoachMemoryFact: Identifiable, Codable, Hashable, Sendable {
    public enum Topic: String, Codable, CaseIterable, Hashable, Sendable {
        case injury, preference, equipment, schedule, goal, other

        /// What the memory list and the prompt call the topic.
        public var displayName: String {
            switch self {
            case .injury: "Injury"
            case .preference: "Preference"
            case .equipment: "Equipment"
            case .schedule: "Schedule"
            case .goal: "Goal"
            case .other: "Other"
            }
        }
    }

    public var id: UUID
    public var text: String
    public var topic: Topic
    public var createdAt: Date
    /// After this the fact is dropped on the next validation ("back squats off for 6 weeks").
    public var expiresAt: Date?
    /// The chat that stated it, so the memory list can say where a fact came from.
    public var sourceThreadID: UUID?

    public init(
        id: UUID = UUID(), text: String, topic: Topic, createdAt: Date, expiresAt: Date? = nil,
        sourceThreadID: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.topic = topic
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.sourceThreadID = sourceThreadID
    }

    public func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }
}

/// Where the facts live. The app implements it over a file; a test hands in an in-memory one.
/// Implementations store what `CoachMemoryValidation` hands back, so every reader sees the
/// same deduped, capped, unexpired list. Main-actor because the tool executor that calls it is.
@MainActor
public protocol CoachMemoryStore: AnyObject {
    func facts() -> [CoachMemoryFact]
    func replaceAll(_ facts: [CoachMemoryFact]) throws
}

/// The rules a facts list is held to: text trimmed and capped, near-duplicates collapsed with
/// the newest winning, expired facts dropped, at most `maxFacts` kept (newest first).
public enum CoachMemoryValidation {
    public static let maxTextLength = 200
    public static let maxFacts = 60

    /// The text as stored: whitespace collapsed, trimmed, cut to `maxTextLength`. nil when
    /// nothing is left.
    public static func normalizedText(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxTextLength))
    }

    /// The comparison key for duplicates: lower-cased letters and digits only, so "Knees hurt
    /// on leg press." and "knees hurt on leg-press" are the same fact.
    public static func duplicateKey(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// `facts` plus `new`, cleaned up: expired facts gone, an older fact with the same key as
    /// a newer one gone, newest first, capped. `new` is appended before the pass so a restated
    /// fact replaces its earlier version (and refreshes its date and expiry).
    public static func merged(
        _ facts: [CoachMemoryFact], adding new: [CoachMemoryFact] = [], now: Date
    ) -> [CoachMemoryFact] {
        var seen: Set<String> = []
        var kept: [CoachMemoryFact] = []
        // Newest first; on the same instant a fact from `new` beats one already stored.
        let ordered = (new + facts).enumerated()
            .sorted { lhs, rhs in
                lhs.element.createdAt == rhs.element.createdAt
                    ? lhs.offset < rhs.offset : lhs.element.createdAt > rhs.element.createdAt
            }
            .map(\.element)
        for fact in ordered where !fact.isExpired(at: now) {
            guard let text = normalizedText(fact.text) else { continue }
            let key = duplicateKey(text)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            var cleaned = fact
            cleaned.text = text
            kept.append(cleaned)
            if kept.count == maxFacts { break }
        }
        return kept
    }

    /// The facts matching a `recall` call: by topic when given, and by query words (any word
    /// of the query in the text, case-insensitive) when given; everything when neither is.
    public static func matching(
        _ facts: [CoachMemoryFact], topic: CoachMemoryFact.Topic?, query: String?
    ) -> [CoachMemoryFact] {
        let words = (query ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return facts.filter { fact in
            if let topic, fact.topic != topic { return false }
            guard !words.isEmpty else { return true }
            let haystack = fact.text.lowercased()
            return words.contains { haystack.contains($0) }
        }
    }
}
