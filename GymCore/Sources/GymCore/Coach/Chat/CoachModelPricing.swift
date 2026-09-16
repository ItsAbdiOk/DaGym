import Foundation

/// List prices for the chat models, in US dollars per one million tokens, so a thread's token
/// counts can be turned into an estimate without a network call. Approximate OpenRouter list
/// prices as of 2026-09-16; OpenRouter's own `cost` on a response, when it sends one, is the
/// number to trust over this. A model not in the table has no price, and the usage screen
/// shows its tokens only.
public struct CoachModelPricing: Hashable, Sendable {
    public var inputUSDPerMillion: Double
    public var outputUSDPerMillion: Double

    public init(inputUSDPerMillion: Double, outputUSDPerMillion: Double) {
        self.inputUSDPerMillion = inputUSDPerMillion
        self.outputUSDPerMillion = outputUSDPerMillion
    }

    // MARK: - The table (2026-09-16)

    public static let geminiPro = CoachModelPricing(inputUSDPerMillion: 2, outputUSDPerMillion: 12)
    public static let claudeOpus = CoachModelPricing(inputUSDPerMillion: 5, outputUSDPerMillion: 25)
    public static let claudeSonnet = CoachModelPricing(inputUSDPerMillion: 3, outputUSDPerMillion: 15)

    /// By OpenRouter model id, without any `:variant` suffix.
    public static let table: [String: CoachModelPricing] = [
        "google/gemini-3.1-pro-preview": geminiPro,
        "anthropic/claude-opus-5": claudeOpus,
        "anthropic/claude-sonnet-5": claudeSonnet
    ]

    /// The price for a model id; a `:variant` suffix (`:thinking`, `:online`) is ignored, since
    /// OpenRouter bills the base model. nil for a model the table does not know.
    public static func price(forModelID id: String) -> CoachModelPricing? {
        let base = id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? id
        return table[base]
    }

    /// What the given token counts cost at this price.
    public func cost(promptTokens: Int, completionTokens: Int) -> Double {
        (Double(promptTokens) * inputUSDPerMillion + Double(completionTokens) * outputUSDPerMillion)
            / 1_000_000
    }
}

/// Prompt and completion tokens for one model, the shape the estimate reads. The app's usage
/// types map into this so the arithmetic lives here, where it is tested without a simulator.
public struct CoachTokenCount: Hashable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

extension CoachModelPricing {
    /// The estimated cost of tokens spread over several models. nil when any model with tokens
    /// has no price — a partial figure would read as the whole — and 0 when nothing was used.
    public static func estimatedUSD(
        tokensByModel: [String: CoachTokenCount],
        pricing: (String) -> CoachModelPricing? = price(forModelID:)
    ) -> Double? {
        var total = 0.0
        for (model, tokens) in tokensByModel where tokens.promptTokens + tokens.completionTokens > 0 {
            guard let price = pricing(model) else { return nil }
            total += price.cost(promptTokens: tokens.promptTokens, completionTokens: tokens.completionTokens)
        }
        return total
    }
}
