import Foundation
import GymCore

/// The chat screen's pure state and copy: what the error banner says per `OpenRouterError`,
/// the prompts an empty thread suggests, what a draft card lists when expanded (and what Copy
/// writes for it), and where each card sits between proposed and applied. Bubble text is
/// `CoachMarkdown` in GymCore. No SwiftUI here, so `CoachChatSupportTests` covers all of it.
enum CoachChatErrorCopy {
    /// What the banner offers besides dismissing: open Settings for the key, open OpenRouter
    /// for credit, or send the last message again.
    enum Action: Equatable, Sendable {
        case openSettings
        case openOpenRouter
        case retry
    }

    struct Banner: Equatable, Sendable {
        var title: String
        var message: String
        var action: Action?
        var actionTitle: String?
    }

    static let openRouterCreditsURL = URL(string: "https://openrouter.ai/credits")

    /// The store refused a draft: the routine it changes has been deleted since it was proposed.
    static let applyRefused = Banner(
        title: "Couldn't apply", message: "The routine this changes no longer exists. Ask the coach again.",
        action: nil, actionTitle: nil
    )

    static func banner(for error: OpenRouterError) -> Banner {
        switch error {
        case .missingKey:
            Banner(
                title: "No API key", message: "Add your OpenRouter key in Settings to talk to the coach.",
                action: .openSettings, actionTitle: "Open Settings"
            )
        case .unauthorized:
            Banner(
                title: "Key rejected",
                message: "OpenRouter didn't accept the key. Check it in Settings — it may have been revoked.",
                action: .openSettings, actionTitle: "Open Settings"
            )
        case .rateLimited(let retryAfter):
            Banner(
                title: "Slow down",
                message: retryAfter
                    .map { "The model is rate-limited. Try again in \(Int($0.rounded(.up)))s." }
                    ?? "The model is rate-limited. Try again in a moment.",
                action: .retry, actionTitle: "Retry"
            )
        case .insufficientCredits(let detail):
            Banner(
                title: "Out of credit",
                message: "OpenRouter said: \(detail) Top up at openrouter.ai — or, if you pay through a "
                    + "provider key under Integrations, that provider's balance.",
                action: .openOpenRouter, actionTitle: "Open openrouter.ai"
            )
        case .badRequest(let message):
            Banner(
                title: "The model refused",
                message: message.isEmpty ? "OpenRouter rejected the request." : message,
                action: nil, actionTitle: nil
            )
        case .server(let status):
            Banner(
                title: "OpenRouter is having trouble",
                message: "The server answered \(status). Nothing was lost — try again shortly.",
                action: .retry, actionTitle: "Retry"
            )
        case .network:
            Banner(
                title: "No connection",
                message: "Couldn't reach OpenRouter. Check your connection and retry.",
                action: .retry, actionTitle: "Retry"
            )
        case .decoding:
            Banner(
                title: "Unexpected reply",
                message: "OpenRouter sent something DaGym couldn't read. Try again.",
                action: .retry, actionTitle: "Retry"
            )
        }
    }
}

/// What an empty thread offers, so the first question doesn't start from a blank field.
enum CoachChatSuggestedPrompts {
    static let all = [
        "Am I doing enough shoulder volume?",
        "When will I bench 100 kg?",
        "Build me an upper/lower with my machines"
    ]
}

/// The lines a draft card lists when expanded — one per exercise, day or change — so the
/// lifter can read what Apply will do before tapping it.
enum CoachDraftDetail {
    struct Row: Equatable, Sendable, Identifiable {
        var id: Int
        var title: String
        var detail: String?
        /// The drafter's one clause on why this exercise, under the row on routine cards.
        var reason: String?
    }

    static func rows(for draft: CoachChatDraft, formatWeight: (Double) -> String) -> [Row] {
        switch draft {
        case .routine(let proposal):
            exerciseRows(proposal.exercises, formatWeight: formatWeight)
        case .program(let proposal):
            proposal.usesTemplate
                ? [Row(id: 0, title: "Routines from the \(proposal.goal.displayName.lowercased()) template")]
                : proposal.routines.enumerated().map { index, routine in
                    Row(id: index, title: routine.name, detail: Self.countLine(routine))
                }
        case .schedule(let proposal):
            Weekday.ordered(mondayFirst: true).enumerated().map { index, day in
                let routine = proposal.days[day].map { proposal.routineNames[$0] ?? "Routine" }
                return Row(id: index, title: day.displayName, detail: routine ?? "Rest")
            }
        case .deload(let proposal):
            [Row(
                id: 0, title: proposal.exerciseName ?? "Exercise",
                detail: "Working weight down \(Int(proposal.percent.rounded()))%"
            )]
        case .swap(let proposal):
            [
                Row(id: 0, title: "Remove", detail: proposal.fromExerciseName ?? "exercise"),
                Row(id: 1, title: "Add", detail: proposal.toExerciseName ?? "exercise")
            ]
        }
    }

    /// A program card groups its rows per routine: the routine's name and counts as a heading,
    /// its exercises under it. Every other draft is one unnamed section.
    struct Section: Equatable, Sendable, Identifiable {
        var id: Int
        var title: String?
        var subtitle: String?
        var rows: [Row]
    }

    static func sections(for draft: CoachChatDraft, formatWeight: (Double) -> String) -> [Section] {
        guard case .program(let proposal) = draft, !proposal.usesTemplate else {
            return [Section(id: 0, rows: rows(for: draft, formatWeight: formatWeight))]
        }
        return proposal.routines.enumerated().map { index, routine in
            Section(
                id: index, title: routine.name, subtitle: countLine(routine),
                rows: exerciseRows(routine.exercises, formatWeight: formatWeight)
                    .map { row in
                        var row = row
                        row.id += index * 1_000
                        return row
                    }
            )
        }
    }

    /// "4 exercises · 14 sets" — the routine's own summary without its name repeated.
    static func countLine(_ routine: RoutineProposal) -> String {
        let count = routine.exercises.count
        return "\(count) \(count == 1 ? "exercise" : "exercises") · \(routine.setCount) sets"
    }

    private static func exerciseRows(
        _ exercises: [CoachChatExerciseSpec], formatWeight: (Double) -> String
    ) -> [Row] {
        exercises.enumerated().map { index, exercise in
            Row(
                id: index, title: exercise.label, detail: setLine(exercise.sets, formatWeight: formatWeight),
                reason: exercise.reason
            )
        }
    }

    /// The card as plain text for the clipboard: the summary, one line per row with its reason
    /// indented under it, and the routine's notes.
    static func copyText(for draft: CoachChatDraft, formatWeight: (Double) -> String) -> String {
        var lines = [draft.summary]
        for row in rows(for: draft, formatWeight: formatWeight) {
            lines.append(row.detail.map { "- \(row.title): \($0)" } ?? "- \(row.title)")
            if let reason = row.reason { lines.append("  \(reason)") }
        }
        if case .routine(let proposal) = draft, let notes = proposal.notes, !notes.isEmpty {
            lines.append("")
            lines.append(notes)
        }
        return lines.joined(separator: "\n")
    }

    /// "3 × 8 @ 60 kg" when every set matches, else each set spelt out.
    static func setLine(_ sets: [CoachChatSetSpec], formatWeight: (Double) -> String) -> String {
        guard let first = sets.first else { return "No sets" }
        if sets.allSatisfy({ $0 == first }) {
            return "\(sets.count) × \(setText(first, formatWeight: formatWeight))"
        }
        return sets.map { setText($0, formatWeight: formatWeight) }.joined(separator: ", ")
    }

    private static func setText(_ set: CoachChatSetSpec, formatWeight: (Double) -> String) -> String {
        var text = "\(set.targetReps)"
        if let weight = set.targetWeightKg { text += " @ \(formatWeight(weight))" }
        if let rpe = set.rpe { text += " RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))" }
        if set.kind != .working { text += " (\(set.kind.badge))" }
        return text
    }
}

/// Where a draft card sits: still proposed, applied (undo lives in the toast), discarded by
/// the lifter, or not chosen because its linked card (the drafter's or the reviewer's version
/// of the same proposal) was applied instead. Kept by the screen per draft index; the archive
/// doesn't store it, so a restored thread's cards come back as proposed and Apply is refused
/// by the store if the target is gone.
enum CoachDraftCardState: Equatable, Sendable {
    case proposed, applied, discarded, notChosen

    var isSettled: Bool { self != .proposed }

    var caption: String? {
        switch self {
        case .proposed: nil
        case .applied: "Applied"
        case .discarded: "Discarded"
        case .notChosen: "Not chosen"
        }
    }
}

/// Price line for the model picker: "$3.00 in · $15.00 out per 1M tokens". USD because that
/// is what OpenRouter bills in, so the locale is pinned rather than the phone's.
enum CoachModelPricingText {
    private static let usd = Decimal.FormatStyle.Currency(
        code: "USD", locale: Locale(identifier: "en_US")
    ).precision(.fractionLength(2))

    static func line(for pricing: OpenRouterWire.Pricing?) -> String? {
        guard let pricing, let prompt = pricing.promptUSDPerMillion,
              let completion = pricing.completionUSDPerMillion
        else { return nil }
        if prompt == 0, completion == 0 { return "Free" }
        return "\(prompt.formatted(usd)) in · \(completion.formatted(usd)) out per 1M tokens"
    }
}

/// Case-insensitive match on id or name, so "sonnet" finds every Claude Sonnet row.
enum CoachModelSearch {
    static func filter(_ models: [OpenRouterWire.Model], query: String) -> [OpenRouterWire.Model] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return models }
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(trimmed)
                || $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// What the transcript draws: messages as they are, except that a run of identical tool calls
/// (thirty "Searching exercises" chips while the model hunts one exercise at a time) collapses
/// into one chip with a count. Pure, so a test can pin the grouping.
enum CoachChatTranscript {
    enum Entry: Identifiable, Equatable {
        case message(CoachChatMessage)
        case toolGroup(label: String, count: Int, failed: Bool)

        var id: String {
            switch self {
            case .message(let message): message.id.uuidString
            case .toolGroup(let label, let count, let failed): "tool:\(label):\(count):\(failed)"
            }
        }
    }

    static func collapse(_ messages: [CoachChatMessage]) -> [Entry] {
        var entries: [Entry] = []
        for message in messages {
            guard message.role == .tool else {
                entries.append(.message(message))
                continue
            }
            if case .toolGroup(let label, let count, let failed)? = entries.last,
               label == message.text, failed == message.isToolError {
                entries[entries.count - 1] = .toolGroup(label: label, count: count + 1, failed: failed)
            } else {
                entries.append(.toolGroup(label: message.text, count: 1, failed: message.isToolError))
            }
        }
        return entries
    }

    /// The messages of the turn in progress or just finished — the last question and everything
    /// after it. These never fold behind "Show more": the lifter is reading them now.
    static func latestTurnIDs(_ messages: [CoachChatMessage]) -> Set<UUID> {
        guard let start = messages.lastIndex(where: { $0.role == .user }) else {
            return Set(messages.map(\.id))
        }
        return Set(messages[start...].map(\.id))
    }

    /// True while the last thing on screen is the lifter's question or a tool chip — i.e. the
    /// model has not started its reply yet.
    static func isWaitingForText(_ messages: [CoachChatMessage]) -> Bool {
        guard let last = messages.last else { return false }
        switch last.role {
        case .user, .tool: return true
        case .assistant: return last.text.isEmpty
        case .draft, .review: return false
        }
    }
}
