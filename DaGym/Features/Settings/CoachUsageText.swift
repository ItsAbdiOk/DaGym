import Foundation
import GymCore

/// The usage screen's wording: token counts as "12.3K", dollars in USD (what OpenRouter bills
/// in, so the locale is pinned like `CoachModelPricingText`), and the one-line summary the
/// chat's navigation subtitle shows. Pure, so a test can pin each string.
enum CoachUsageText {
    private static let usd = Decimal.FormatStyle.Currency(
        code: "USD", locale: Locale(identifier: "en_US")
    ).precision(.fractionLength(2))
    private static let compact = IntegerFormatStyle<Int>(locale: Locale(identifier: "en_US"))
        .notation(.compactName)
        .precision(.significantDigits(1...3))

    /// "0", "980", "12.3K", "1.2M".
    static func tokens(_ count: Int) -> String {
        count.formatted(compact)
    }

    /// "12.3K in · 4.1K out".
    static func inOut(promptTokens: Int, completionTokens: Int) -> String {
        "\(tokens(promptTokens)) in · \(tokens(completionTokens)) out"
    }

    /// "$0.42", "<$0.01" for a used-but-tiny amount, "$0.00" for nothing at all.
    static func dollars(_ amount: Double) -> String {
        if amount > 0, amount < 0.005 { return "<$0.01" }
        return Decimal(amount).formatted(usd)
    }

    /// "≈ $0.42" for an estimate; "$0.42" when OpenRouter reported the figure itself.
    static func cost(_ amount: Double?, reported: Bool) -> String? {
        guard let amount else { return nil }
        return reported ? dollars(amount) : "≈ \(dollars(amount))"
    }

    /// The chat header's subtitle: "16.4K tokens · ≈ $0.12", or the tokens alone when a model
    /// has no known price; nil before the thread has used anything.
    static func threadLine(_ usage: CoachChatUsage) -> String? {
        guard usage.totalTokens > 0 else { return nil }
        let tokens = "\(tokens(usage.totalTokens)) tokens"
        guard let cost = cost(usage.estimatedUSD(), reported: usage.costUSD != nil) else { return tokens }
        return "\(tokens) · \(cost)"
    }
}
