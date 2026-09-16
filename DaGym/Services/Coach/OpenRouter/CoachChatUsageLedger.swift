import Foundation
import GymCore
import os

/// Running token totals across every chat thread, per model, for the usage screen in
/// Settings. Separate from the threads themselves so "Reset statistics" can zero the counters
/// while every transcript (and its own usage) stays on disk. Lives in `UserDefaults` as one
/// JSON blob, local to the phone like the archive.
struct CoachChatUsageLedger: Codable, Equatable, Sendable {
    var byModel: [String: CoachChatModelUsage] = [:]
    /// When the counters started — first use, or the last reset. nil until either happens.
    var since: Date?
    /// Turns booked since `since` (one per model reply, so a tool round counts as one).
    var replies = 0

    var promptTokens: Int { byModel.values.reduce(0) { $0 + $1.promptTokens } }
    var completionTokens: Int { byModel.values.reduce(0) { $0 + $1.completionTokens } }
    var totalTokens: Int { promptTokens + completionTokens }
    var isEmpty: Bool { byModel.isEmpty }
    /// Every model's dollars came from OpenRouter itself, so the total is not an estimate.
    var isFullyReported: Bool { !byModel.isEmpty && byModel.values.allSatisfy { $0.costUSD != nil } }

    /// Models ordered by tokens spent, most first, for the breakdown rows.
    var modelsBySpend: [String] {
        byModel.keys.sorted { lhs, rhs in
            let left = byModel[lhs].map { $0.promptTokens + $0.completionTokens } ?? 0
            let right = byModel[rhs].map { $0.promptTokens + $0.completionTokens } ?? 0
            return left == right ? lhs < rhs : left > right
        }
    }

    /// The sum over every model: OpenRouter's reported cost where it sent one, the list-price
    /// estimate otherwise; nil when a model with tokens is priced by neither.
    func estimatedUSD(
        pricing: (String) -> CoachModelPricing? = CoachModelPricing.price(forModelID:)
    ) -> Double? {
        var total = 0.0
        for (model, usage) in byModel where usage.promptTokens + usage.completionTokens > 0 {
            guard let cost = usage.estimatedUSD(model: model, pricing: pricing) else { return nil }
            total += cost
        }
        return total
    }

    mutating func record(_ usage: OpenRouterWire.Usage, model: String, at date: Date) {
        if since == nil { since = date }
        replies += 1
        byModel[model, default: CoachChatModelUsage()].add(usage)
    }
}

/// Where the ledger is kept: one `UserDefaults` key. `standard` is the app's; a test hands in
/// its own suite. Main-actor like the engine and the screens that read it.
@MainActor
struct CoachChatUsageLedgerStore {
    static let key = "coachChatUsageLedger"
    static let standard = CoachChatUsageLedgerStore(defaults: .standard)

    private static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "coachChat")

    let defaults: UserDefaults

    func load() -> CoachChatUsageLedger {
        guard let data = defaults.data(forKey: Self.key) else { return CoachChatUsageLedger() }
        do {
            return try JSONDecoder().decode(CoachChatUsageLedger.self, from: data)
        } catch {
            let reason = error.localizedDescription
            Self.logger.error("Unreadable usage ledger, starting over: \(reason, privacy: .public)")
            return CoachChatUsageLedger()
        }
    }

    func save(_ ledger: CoachChatUsageLedger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Books one reply's usage against `model`.
    func record(_ usage: OpenRouterWire.Usage, model: String, at date: Date) {
        var ledger = load()
        ledger.record(usage, model: model, at: date)
        save(ledger)
    }

    /// Zeroes the counters; the threads in the archive are untouched.
    func reset(at date: Date) {
        var ledger = CoachChatUsageLedger()
        ledger.since = date
        save(ledger)
    }
}
