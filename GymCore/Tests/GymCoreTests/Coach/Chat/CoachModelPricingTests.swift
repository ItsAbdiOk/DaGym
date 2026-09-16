import Foundation
import Testing

@testable import GymCore

@Suite("CoachModelPricing: list prices turn token counts into a dollar estimate")
struct CoachModelPricingTests {
    @Test("the default drafter and reviewer are priced; a variant suffix is ignored; unknown is nil")
    func lookup() {
        #expect(CoachModelPricing.price(forModelID: "google/gemini-3.1-pro-preview") == .geminiPro)
        #expect(CoachModelPricing.price(forModelID: "anthropic/claude-opus-5") == .claudeOpus)
        #expect(CoachModelPricing.price(forModelID: "anthropic/claude-sonnet-5:thinking") == .claudeSonnet)
        #expect(CoachModelPricing.price(forModelID: "openai/gpt-5") == nil)
    }

    @Test("cost is input and output tokens at their per-million rates")
    func cost() {
        let cost = CoachModelPricing.claudeOpus.cost(promptTokens: 1_000_000, completionTokens: 100_000)
        #expect(abs(cost - 7.5) < 0.000_001)
        #expect(CoachModelPricing.geminiPro.cost(promptTokens: 0, completionTokens: 0) == 0)
    }

    @Test("the estimate sums every priced model and is nil when one with tokens is unknown")
    func estimate() {
        let usage = [
            "google/gemini-3.1-pro-preview": CoachTokenCount(promptTokens: 500_000, completionTokens: 50_000),
            "anthropic/claude-opus-5": CoachTokenCount(promptTokens: 200_000, completionTokens: 20_000)
        ]
        let estimate = CoachModelPricing.estimatedUSD(tokensByModel: usage)
        // Gemini 1.00 + 0.60, Opus 1.00 + 0.50.
        #expect(estimate.map { abs($0 - 3.1) < 0.000_001 } == true)
        var withUnknown = usage
        withUnknown["openai/gpt-5"] = CoachTokenCount(promptTokens: 10, completionTokens: 1)
        #expect(CoachModelPricing.estimatedUSD(tokensByModel: withUnknown) == nil)
        // An unknown model that was never actually used does not spoil the figure.
        withUnknown["openai/gpt-5"] = CoachTokenCount(promptTokens: 0, completionTokens: 0)
        #expect(CoachModelPricing.estimatedUSD(tokensByModel: withUnknown) != nil)
        #expect(CoachModelPricing.estimatedUSD(tokensByModel: [:]) == 0)
    }
}
