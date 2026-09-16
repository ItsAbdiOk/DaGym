import Foundation
import GymCore

/// What a tool returns to the engine: JSON for the model, or a validated proposal for the
/// lifter's card (with the compact JSON the model sees in its place).
enum CoachChatToolResult: Sendable {
    case json(String)
    case draft(CoachChatDraft, summaryJSON: String)
}

/// The app-side implementation of the tool catalogue. `WorkoutStore` implements it; tests hand
/// in a fake. Main-actor because the store is. Throwing is fine: the engine turns the error
/// into `{"error": …}` for the model and never shows it as a failure.
@MainActor
protocol CoachChatToolExecutor: AnyObject {
    func execute(name: String, argumentsJSON: String) async throws -> CoachChatToolResult
}

/// One entry of a chat thread as the screen shows it — not the wire transcript, which the
/// engine keeps separately and rebuilds from these on restore.
struct CoachChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant
        /// A compact activity chip ("Read exercise history"), not a bubble.
        case tool
        /// A proposal card; `draftIndex` points into the thread's `drafts`.
        case draft
        /// The second-opinion model's words: its streamed text, its verdict line, or the muted
        /// note when it failed. `reviewIndex` points into the thread's `reviews`.
        case review
    }

    var id: UUID
    var role: Role
    var text: String
    var toolName: String?
    var draftIndex: Int?
    /// For `.review` rows (and the reviewer's tool chips and draft cards): which review they
    /// belong to. Optional so threads archived before the second opinion existed decode.
    var reviewIndex: Int?
    /// The tool call failed; the chip says so in passing while the model retries or explains.
    var isToolError = false
    /// The lifter tapped stop mid-answer; the bubble shows a "stopped" marker.
    var isStopped = false
    /// An app-written line ("Couldn't reach OpenRouter…"), not the model's words: drawn muted
    /// and never replayed to the model. Optional so threads archived before it existed decode.
    var isNote: Bool?
    var sentAt: Date

    static func user(_ text: String, at date: Date) -> CoachChatMessage {
        CoachChatMessage(id: UUID(), role: .user, text: text, sentAt: date)
    }

    static func assistant(_ text: String, at date: Date) -> CoachChatMessage {
        CoachChatMessage(id: UUID(), role: .assistant, text: text, sentAt: date)
    }

    static func note(_ text: String, at date: Date) -> CoachChatMessage {
        CoachChatMessage(id: UUID(), role: .assistant, text: text, isNote: true, sentAt: date)
    }

    static func tool(_ name: String, at date: Date) -> CoachChatMessage {
        CoachChatMessage(id: UUID(), role: .tool, text: label(forTool: name), toolName: name, sentAt: date)
    }

    static func draft(index: Int, summary: String, at date: Date) -> CoachChatMessage {
        CoachChatMessage(id: UUID(), role: .draft, text: summary, draftIndex: index, sentAt: date)
    }

    static func review(_ text: String, index: Int, isNote: Bool = false, at date: Date) -> CoachChatMessage {
        CoachChatMessage(
            id: UUID(), role: .review, text: text, reviewIndex: index, isNote: isNote ? true : nil,
            sentAt: date
        )
    }

    /// The catalogue's own label for a known tool ("Reading exercise history"); an unknown name
    /// (the model invented one) is humanised so the chip still reads.
    static func label(forTool name: String) -> String {
        if let known = CoachChatToolName(rawValue: name) { return known.activityLabel }
        let words = name.split(separator: "_").map(String.init)
        guard let verb = words.first else { return name }
        let rest = words.dropFirst().joined(separator: " ")
        let action: String
        switch verb {
        case "get": action = "Reading"
        case "list": action = "Listing"
        case "search": action = "Searching"
        case "propose": action = "Drafting"
        default: action = verb.capitalized
        }
        return rest.isEmpty ? action : "\(action) \(rest)"
    }
}

/// Token counts summed over the thread, plus cost when OpenRouter reports it. The totals
/// cover both models; `byModel` splits them by OpenRouter model id for the usage line.
struct CoachChatUsage: Codable, Equatable, Sendable {
    var promptTokens = 0
    var completionTokens = 0
    var costUSD: Double?
    var byModel: [String: CoachChatModelUsage] = [:]

    init(promptTokens: Int = 0, completionTokens: Int = 0, costUSD: Double? = nil,
         byModel: [String: CoachChatModelUsage] = [:]) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.costUSD = costUSD
        self.byModel = byModel
    }

    /// `byModel` is missing from threads archived before the second opinion existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        byModel = try container.decodeIfPresent([String: CoachChatModelUsage].self, forKey: .byModel) ?? [:]
    }

    mutating func add(_ usage: OpenRouterWire.Usage, model: String) {
        promptTokens += usage.promptTokens
        completionTokens += usage.completionTokens
        if let cost = usage.cost { costUSD = (costUSD ?? 0) + cost }
        byModel[model, default: CoachChatModelUsage()].add(usage)
    }

    var totalTokens: Int { promptTokens + completionTokens }

    /// The thread's cost from the list-price table: OpenRouter's own figure when it reported
    /// one, else `CoachModelPricing` over `byModel`; nil when a model used has no known price.
    func estimatedUSD(
        pricing: (String) -> CoachModelPricing? = CoachModelPricing.price(forModelID:)
    ) -> Double? {
        if let costUSD { return costUSD }
        return CoachModelPricing.estimatedUSD(
            tokensByModel: byModel.mapValues(\.tokenCount), pricing: pricing
        )
    }
}

/// One model's share of a thread's usage.
struct CoachChatModelUsage: Codable, Equatable, Sendable {
    var promptTokens = 0
    var completionTokens = 0
    var costUSD: Double?

    mutating func add(_ usage: OpenRouterWire.Usage) {
        promptTokens += usage.promptTokens
        completionTokens += usage.completionTokens
        if let cost = usage.cost { costUSD = (costUSD ?? 0) + cost }
    }

    var tokenCount: CoachTokenCount {
        CoachTokenCount(promptTokens: promptTokens, completionTokens: completionTokens)
    }

    /// OpenRouter's reported cost, else the list-price estimate for `model`; nil when unknown.
    func estimatedUSD(
        model: String, pricing: (String) -> CoachModelPricing? = CoachModelPricing.price(forModelID:)
    ) -> Double? {
        if let costUSD { return costUSD }
        return pricing(model)?.cost(promptTokens: promptTokens, completionTokens: completionTokens)
    }
}

/// Which model wrote a draft. Kept beside the thread's `drafts` (same index) rather than on
/// the GymCore `CoachChatDraft`, which is the tool contract and knows nothing about models.
enum CoachChatDraftOrigin: String, Codable, Equatable, Sendable {
    case drafter, reviewer
}

/// One conversation, as persisted by `CoachChatArchive` and restored into a `CoachChatEngine`.
struct CoachChatThread: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var messages: [CoachChatMessage] = []
    var drafts: [CoachChatDraft] = []
    /// Parallel to `drafts`; a draft with no entry (an older archive) is the drafter's.
    var draftOrigins: [CoachChatDraftOrigin] = []
    var reviews: [CoachChatReview] = []
    var usage = CoachChatUsage()

    init(
        id: UUID, createdAt: Date, updatedAt: Date, messages: [CoachChatMessage] = [],
        drafts: [CoachChatDraft] = [], draftOrigins: [CoachChatDraftOrigin] = [],
        reviews: [CoachChatReview] = [], usage: CoachChatUsage = CoachChatUsage()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.drafts = drafts
        self.draftOrigins = draftOrigins
        self.reviews = reviews
        self.usage = usage
    }

    /// `draftOrigins` and `reviews` are missing from threads archived before the second
    /// opinion existed; everything else was always written.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        messages = try container.decodeIfPresent([CoachChatMessage].self, forKey: .messages) ?? []
        drafts = try container.decodeIfPresent([CoachChatDraft].self, forKey: .drafts) ?? []
        draftOrigins = try container.decodeIfPresent([CoachChatDraftOrigin].self, forKey: .draftOrigins) ?? []
        reviews = try container.decodeIfPresent([CoachChatReview].self, forKey: .reviews) ?? []
        usage = try container.decodeIfPresent(CoachChatUsage.self, forKey: .usage) ?? CoachChatUsage()
    }

    /// Who wrote `drafts[index]`.
    func origin(ofDraft index: Int) -> CoachChatDraftOrigin {
        draftOrigins.indices.contains(index) ? draftOrigins[index] : .drafter
    }

    /// The first user message, trimmed to a line, for the thread list.
    var title: String {
        guard let first = messages.first(where: { $0.role == .user })?.text else { return "New chat" }
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        return line.count > 60 ? String(line.prefix(57)) + "…" : line
    }
}

/// A thread list row: what the toolbar menu shows without holding every transcript in memory.
struct CoachChatThreadSummary: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var updatedAt: Date
    var messageCount: Int
}
