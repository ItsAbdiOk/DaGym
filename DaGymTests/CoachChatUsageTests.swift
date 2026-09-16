import Foundation
import GymCore
import Testing

@testable import DaGym

@MainActor
@Suite("Coach chat usage: the ledger, the cost estimate and the usage screen's wording")
struct CoachChatUsageTests {
    private typealias Fake = FakeOpenRouterTransport

    nonisolated private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let drafter = CoachChatConfiguration.defaultModelID

    private func suite() -> UserDefaults {
        let name = "coach-usage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a thread's cost is OpenRouter's figure when reported, else the list-price estimate")
    func threadEstimate() {
        var usage = CoachChatUsage()
        usage.add(OpenRouterWire.Usage(promptTokens: 1_000_000, completionTokens: 0), model: Self.drafter)
        usage.add(
            OpenRouterWire.Usage(promptTokens: 0, completionTokens: 100_000),
            model: CoachChatConfiguration.defaultReviewerModelID
        )
        // Gemini 2.00 in, Opus 2.50 out.
        #expect(usage.estimatedUSD().map { abs($0 - 4.5) < 0.000_001 } == true)
        usage.add(OpenRouterWire.Usage(promptTokens: 10, completionTokens: 1), model: "openai/gpt-5")
        #expect(usage.estimatedUSD() == nil)
        let reported = OpenRouterWire.Usage(promptTokens: 1, completionTokens: 1, cost: 0.25)
        usage.add(reported, model: "openai/gpt-5")
        #expect(usage.estimatedUSD() == 0.25)
        #expect(usage.byModel["openai/gpt-5"]?.estimatedUSD(model: "openai/gpt-5") == 0.25)
    }

    @Test("the ledger books every reply, survives a reload, and reset keeps only the date")
    func ledgerRoundTrip() {
        let store = CoachChatUsageLedgerStore(defaults: suite())
        #expect(store.load() == CoachChatUsageLedger())
        let first = OpenRouterWire.Usage(promptTokens: 100, completionTokens: 10)
        store.record(first, model: Self.drafter, at: Self.now)
        let second = OpenRouterWire.Usage(promptTokens: 50, completionTokens: 5)
        store.record(second, model: "x/y", at: Self.now + 60)
        let ledger = store.load()
        #expect(ledger.since == Self.now)
        #expect(ledger.replies == 2)
        #expect(ledger.promptTokens == 150)
        #expect(ledger.completionTokens == 15)
        #expect(ledger.modelsBySpend == [Self.drafter, "x/y"])
        #expect(ledger.estimatedUSD() == nil)
        #expect(ledger.isFullyReported == false)
        store.reset(at: Self.now + 120)
        let reset = store.load()
        #expect(reset.isEmpty)
        #expect(reset.replies == 0)
        #expect(reset.since == Self.now + 120)
    }

    @Test("the engine books each reply's usage to the ledger as well as the thread")
    func engineFeedsLedger() async {
        let store = CoachChatUsageLedgerStore(defaults: suite())
        let transport = Fake([Fake.Reply(lines: Fake.sse([
            Fake.text("Rest."), Fake.finish("stop"), Fake.usage(prompt: 40, completion: 4)
        ]))])
        let engine = CoachChatEngine(
            client: OpenRouterClient(apiKey: { "or-test" }, transport: transport),
            executor: FakeCoachChatToolExecutor(),
            configuration: CoachChatConfiguration(reviewerModelID: nil, consentGiven: true),
            systemPrompt: "You are a coach.", tools: [], ledger: store, clock: { Self.now }
        )
        await engine.send("Deload?")
        let ledger = store.load()
        #expect(ledger.byModel[Self.drafter] == CoachChatModelUsage(promptTokens: 40, completionTokens: 4))
        #expect(ledger.since == Self.now)
        #expect(engine.usage.promptTokens == 40)
    }

    @Test("usage text: compact tokens, USD with a floor, and the chat's subtitle")
    func wording() {
        #expect(CoachUsageText.tokens(0) == "0")
        #expect(CoachUsageText.tokens(980) == "980")
        #expect(CoachUsageText.tokens(12_340) == "12.3K")
        #expect(CoachUsageText.tokens(1_200_000) == "1.2M")
        #expect(CoachUsageText.inOut(promptTokens: 1500, completionTokens: 20) == "1.5K in · 20 out")
        #expect(CoachUsageText.dollars(0) == "$0.00")
        #expect(CoachUsageText.dollars(0.004) == "<$0.01")
        #expect(CoachUsageText.dollars(0.42) == "$0.42")
        #expect(CoachUsageText.cost(nil, reported: false) == nil)
        #expect(CoachUsageText.cost(1.5, reported: true) == "$1.50")
        #expect(CoachUsageText.cost(1.5, reported: false) == "≈ $1.50")
        #expect(CoachUsageText.threadLine(CoachChatUsage()) == nil)
        var usage = CoachChatUsage()
        usage.add(OpenRouterWire.Usage(promptTokens: 16_000, completionTokens: 400), model: Self.drafter)
        // 16k × $2 + 400 × $12 per million = $0.0368.
        #expect(CoachUsageText.threadLine(usage) == "16.4K tokens · ≈ $0.04")
        usage.add(OpenRouterWire.Usage(promptTokens: 100, completionTokens: 0), model: "openai/gpt-5")
        #expect(CoachUsageText.threadLine(usage) == "16.5K tokens")
    }
}
