import Foundation
import GymCore

/// The memory tools: `remember` files a fact through the `CoachMemoryStore` the executor was
/// given, `recall` reads them back filtered. Without a store (a build or test that did not
/// wire one) both answer with an error the model can read, never a crash.
extension StoreCoachChatToolExecutor {
    struct RememberArguments: Decodable {
        var text: String
        var topic: String
        var expiresInDays: Int?
        enum CodingKeys: String, CodingKey {
            case text, topic
            case expiresInDays = "expires_in_days"
        }
    }

    struct RecallArguments: Decodable {
        var topic: String?
        var query: String?
    }

    struct FactPayload: Codable {
        var id: UUID
        var text: String
        var topic: String
        var createdAt: Date
        var expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, text, topic
            case createdAt = "created_at"
            case expiresAt = "expires_at"
        }

        init(_ fact: CoachMemoryFact) {
            id = fact.id
            text = fact.text
            topic = fact.topic.rawValue
            createdAt = fact.createdAt
            expiresAt = fact.expiresAt
        }
    }

    struct RememberPayload: Codable {
        var remembered: FactPayload
        var factCount: Int
        enum CodingKeys: String, CodingKey {
            case remembered
            case factCount = "fact_count"
        }
    }

    // MARK: - remember

    func remember(_ arguments: RememberArguments) throws -> RememberPayload {
        let memory = try memoryStore()
        guard let text = CoachMemoryValidation.normalizedText(arguments.text) else {
            throw CoachChatToolError.badArguments("text is empty")
        }
        guard let topic = CoachMemoryFact.Topic(rawValue: arguments.topic.lowercased()) else {
            let topics = CoachMemoryFact.Topic.allCases.map(\.rawValue).joined(separator: ", ")
            throw CoachChatToolError.badArguments("topic must be one of \(topics)")
        }
        let expiryRange = 1...CoachChatToolCatalog.maxExpiryDays
        if let days = arguments.expiresInDays, !expiryRange.contains(days) {
            throw CoachChatToolError.badArguments("expires_in_days must be 1–\(expiryRange.upperBound)")
        }
        let now = now()
        let fact = CoachMemoryFact(
            text: text, topic: topic, createdAt: now,
            expiresAt: arguments.expiresInDays.flatMap { calendar.date(byAdding: .day, value: $0, to: now) },
            sourceThreadID: sourceThreadID
        )
        let merged = CoachMemoryValidation.merged(memory.facts(), adding: [fact], now: now)
        try memory.replaceAll(merged)
        return RememberPayload(remembered: FactPayload(fact), factCount: merged.count)
    }

    // MARK: - recall

    func recall(_ arguments: RecallArguments) throws -> [String: [FactPayload]] {
        let memory = try memoryStore()
        let topic = try arguments.topic.map { raw -> CoachMemoryFact.Topic in
            guard let topic = CoachMemoryFact.Topic(rawValue: raw.lowercased()) else {
                throw CoachChatToolError.badArguments("unknown topic '\(raw)'")
            }
            return topic
        }
        let matches = CoachMemoryValidation.matching(memory.facts(), topic: topic, query: arguments.query)
        return ["facts": matches.map(FactPayload.init)]
    }

    private func memoryStore() throws -> any CoachMemoryStore {
        guard let memory else {
            throw CoachChatToolError.notFound("Memory is not available; carry on without it.")
        }
        return memory
    }
}
