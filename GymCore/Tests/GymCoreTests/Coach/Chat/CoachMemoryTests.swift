import Foundation
import Testing

@testable import GymCore

@Suite("CoachMemory: facts are cleaned, deduped, capped, expired and printed into the prompt")
struct CoachMemoryTests {
    private let now = CoachTestSupport.date("2026-09-15T08:00:00Z")

    private func fact(
        _ text: String, topic: CoachMemoryFact.Topic = .other, daysAgo: Int = 0, expiresInDays: Int? = nil
    ) -> CoachMemoryFact {
        let created = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return CoachMemoryFact(
            text: text, topic: topic, createdAt: created,
            expiresAt: expiresInDays.map { created.addingTimeInterval(Double($0) * 86_400) }
        )
    }

    @Test("text is collapsed, trimmed and cut at 200 characters; blank text is nothing")
    func normalizedText() {
        let messy = "  knees   hurt\n on leg press "
        #expect(CoachMemoryValidation.normalizedText(messy) == "knees hurt on leg press")
        #expect(CoachMemoryValidation.normalizedText("   \n") == nil)
        let long = String(repeating: "a", count: 250)
        #expect(CoachMemoryValidation.normalizedText(long)?.count == CoachMemoryValidation.maxTextLength)
    }

    @Test("near-identical text is one fact and the newest version wins")
    func dedupe() {
        let old = fact("Knees hurt on leg press.", topic: .injury, daysAgo: 10)
        let restated = fact("knees hurt on leg-press", topic: .injury)
        let other = fact("Trains Tuesday and Thursday", topic: .schedule, daysAgo: 3)
        let merged = CoachMemoryValidation.merged([old, other], adding: [restated], now: now)
        #expect(merged.map(\.id) == [restated.id, other.id])
        #expect(merged.first?.text == "knees hurt on leg-press")
        // Stated twice in the same instant (a fixed clock): the new one still wins.
        let sameInstant = fact("Knees hurt on leg press!", topic: .injury)
        let tie = CoachMemoryValidation.merged([restated], adding: [sameInstant], now: now)
        #expect(tie.map(\.id) == [sameInstant.id])
    }

    @Test("expired facts are dropped and the list is capped at 60, newest first")
    func expiryAndCap() {
        let expired = fact("Back squats off", topic: .injury, daysAgo: 50, expiresInDays: 42)
        let live = fact("Hack squat instead", topic: .preference, daysAgo: 50, expiresInDays: 60)
        var many = (0..<70).map { fact("Fact number \($0)", daysAgo: $0 + 1) }
        many.append(contentsOf: [expired, live])
        let merged = CoachMemoryValidation.merged(many, now: now)
        #expect(merged.count == CoachMemoryValidation.maxFacts)
        #expect(!merged.contains { $0.id == expired.id })
        #expect(merged.contains { $0.id == live.id })
        #expect(merged.first?.text == "Fact number 0")
        #expect(zip(merged, merged.dropFirst()).allSatisfy { $0.createdAt >= $1.createdAt })
    }

    @Test("recall filters by topic and by any query word")
    func matching() {
        let facts = [
            fact("Knees hurt on leg press", topic: .injury),
            fact("No cable stack at home", topic: .equipment),
            fact("Hates burpees", topic: .preference)
        ]
        #expect(CoachMemoryValidation.matching(facts, topic: .injury, query: nil).map(\.text) == [
            "Knees hurt on leg press"
        ])
        #expect(CoachMemoryValidation.matching(facts, topic: nil, query: "cable knee").count == 2)
        #expect(CoachMemoryValidation.matching(facts, topic: .equipment, query: "knee").isEmpty)
        #expect(CoachMemoryValidation.matching(facts, topic: nil, query: "  ").count == 3)
    }

    @Test("the prompt block lists the newest 15 with topic and date, and counts the rest")
    func promptBlock() {
        let calendar = CoachTestSupport.calendar
        #expect(CoachChatPrompt.memoryBlock([], calendar: calendar).isEmpty)
        let one = fact("Knees hurt on leg press", topic: .injury, daysAgo: 2, expiresInDays: 30)
        let block = CoachChatPrompt.memoryBlock([one], calendar: calendar)
        #expect(block.contains("What you remember from earlier chats"))
        #expect(block.contains("- [injury, 2026-09-13, until 2026-10-13] Knees hurt on leg press"))
        #expect(!block.contains("older facts"))
        let many = (0..<20).map { fact("Fact \($0)", daysAgo: $0) }
        let capped = CoachChatPrompt.memoryBlock(many.shuffled(), calendar: calendar)
        #expect(capped.components(separatedBy: "\n- [").count - 1 == CoachChatPrompt.maxMemoryLines)
        #expect(capped.contains("Fact 0"))
        #expect(!capped.contains("Fact 15\n"))
        #expect(capped.contains("(5 older facts are available through recall.)"))
        let profile = LifterProfileFacts(unit: .kg)
        let prompt = CoachChatPrompt.system(profile: profile, memory: [one], now: now, calendar: calendar)
        #expect(prompt.contains("Knees hurt on leg press"))
        #expect(CoachChatPrompt.houseRules.first?.contains("call remember once") == true)
        #expect(CoachChatToolCatalog.names.contains("remember"))
        #expect(CoachChatToolCatalog.reviewerTools.contains { $0.name == "recall" })
    }
}
