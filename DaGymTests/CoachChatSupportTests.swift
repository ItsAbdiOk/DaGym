import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("Coach chat screen support")
struct CoachChatSupportTests {
    // MARK: - Error copy

    @Test("Every error kind has a title, a message and the right action")
    func errorCopyPerKind() {
        let cases: [(OpenRouterError, CoachChatErrorCopy.Action?)] = [
            (.missingKey, .openSettings),
            (.unauthorized, .openSettings),
            (.rateLimited(retryAfter: nil), .retry),
            (.insufficientCredits, .openOpenRouter),
            (.badRequest("nope"), nil),
            (.server(503), .retry),
            (.network(URLError(.notConnectedToInternet)), .retry),
            (.decoding, .retry)
        ]
        for (error, action) in cases {
            let banner = CoachChatErrorCopy.banner(for: error)
            #expect(!banner.title.isEmpty)
            #expect(!banner.message.isEmpty)
            #expect(banner.action == action)
            #expect((banner.actionTitle != nil) == (action != nil))
        }
    }

    @Test("Rate limit copy carries the retry-after seconds, rounded up")
    func rateLimitedCopy() {
        let banner = CoachChatErrorCopy.banner(for: .rateLimited(retryAfter: 4.2))
        #expect(banner.message.contains("5s"))
    }

    @Test("Bad request shows the server's line and falls back when it is empty")
    func badRequestCopy() {
        #expect(CoachChatErrorCopy.banner(for: .badRequest("Too long")).message == "Too long")
        #expect(!CoachChatErrorCopy.banner(for: .badRequest("")).message.isEmpty)
    }

    // MARK: - Markdown-lite

    @Test("Paragraphs and bullets split; blank lines separate paragraphs")
    func textBlocks() {
        let text = "First line\ncontinues here.\n\n- one\n* two\n• three\n1. four\n\nLast."
        let blocks = CoachChatTextBlocks.parse(text)
        #expect(blocks == [
            .paragraph("First line continues here."),
            .bullets(["one", "two", "three", "four"]),
            .paragraph("Last.")
        ])
    }

    @Test("Empty and whitespace text yields no blocks")
    func emptyText() {
        #expect(CoachChatTextBlocks.parse("").isEmpty)
        #expect(CoachChatTextBlocks.parse("  \n\n ").isEmpty)
    }

    // MARK: - Draft detail

    private func kg(_ value: Double) -> String { "\(Int(value)) kg" }

    @Test("Routine rows collapse identical sets to N × reps @ weight")
    func routineRows() {
        let proposal = RoutineProposal(
            name: "Upper",
            exercises: [
                CoachChatExerciseSpec(
                    exerciseName: "Bench Press",
                    sets: Array(repeating: CoachChatSetSpec(targetReps: 8, targetWeightKg: 60), count: 3)
                ),
                CoachChatExerciseSpec(
                    exerciseName: "Row",
                    sets: [
                        CoachChatSetSpec(targetReps: 10),
                        CoachChatSetSpec(kind: .amrap, targetReps: 12, rpe: 9)
                    ]
                )
            ]
        )
        let rows = CoachDraftDetail.rows(for: .routine(proposal), formatWeight: kg)
        #expect(rows.map(\.title) == ["Bench Press", "Row"])
        #expect(rows[0].detail == "3 × 8 @ 60 kg")
        #expect(rows[1].detail == "10, 12 RPE 9 (A+)")
    }

    @Test("Schedule rows list every weekday, rest days included")
    func scheduleRows() {
        let id = UUID()
        let proposal = ScheduleProposal(days: [.monday: id], routineNames: [id: "Push"])
        let rows = CoachDraftDetail.rows(for: .schedule(proposal), formatWeight: kg)
        #expect(rows.count == 7)
        #expect(rows.first?.detail == "Push")
        #expect(rows.last?.detail == "Rest")
    }

    @Test("Template programs, deloads and swaps read as one or two lines")
    func otherRows() {
        let program = ProgramProposal(name: "Base", goal: .strength, daysPerWeek: 3)
        #expect(CoachDraftDetail.rows(for: .program(program), formatWeight: kg).count == 1)
        let deload = DeloadProposal(exerciseName: "Squat", percent: 10)
        let deloadRows = CoachDraftDetail.rows(for: .deload(deload), formatWeight: kg)
        #expect(deloadRows.first?.detail == "Working weight down 10%")
        let swap = SwapProposal(routineID: UUID(), fromExerciseName: "A", toExerciseName: "B")
        #expect(CoachDraftDetail.rows(for: .swap(swap), formatWeight: kg).map(\.detail) == ["A", "B"])
    }

    // MARK: - Card state

    @Test("Only applied and discarded cards are settled and captioned")
    func cardState() {
        #expect(!CoachDraftCardState.proposed.isSettled)
        #expect(CoachDraftCardState.proposed.caption == nil)
        #expect(CoachDraftCardState.applied.caption == "Applied")
        #expect(CoachDraftCardState.discarded.caption == "Discarded")
    }

    // MARK: - Model picker helpers

    @Test("Pricing reads per million tokens in USD; free models say so; missing pricing is nil")
    func pricingLine() {
        let paid = OpenRouterWire.Pricing(prompt: "0.000003", completion: "0.000015")
        #expect(CoachModelPricingText.line(for: paid) == "$3.00 in · $15.00 out per 1M tokens")
        let free = OpenRouterWire.Pricing(prompt: "0", completion: "0")
        #expect(CoachModelPricingText.line(for: free) == "Free")
        #expect(CoachModelPricingText.line(for: nil) == nil)
        #expect(CoachModelPricingText.line(for: OpenRouterWire.Pricing(prompt: nil, completion: "1")) == nil)
    }

    @Test("Search matches id or name, case-insensitively, and blank returns all")
    func modelSearch() {
        let models = [
            OpenRouterWire.Model(id: "anthropic/claude-sonnet-5", name: "Claude Sonnet 5"),
            OpenRouterWire.Model(id: "openai/gpt-5", name: "GPT-5")
        ]
        #expect(CoachModelSearch.filter(models, query: "").count == 2)
        #expect(CoachModelSearch.filter(models, query: "SONNET").map(\.id) == ["anthropic/claude-sonnet-5"])
        #expect(CoachModelSearch.filter(models, query: "openai/").map(\.id) == ["openai/gpt-5"])
    }

    @Test("Suggested prompts are three distinct lines")
    func suggestedPrompts() {
        #expect(CoachChatSuggestedPrompts.all.count == 3)
        #expect(Set(CoachChatSuggestedPrompts.all).count == 3)
    }

    @Test("a run of identical tool chips collapses to one with a count; the thinking row waits for text")
    func transcriptCollapsesRepeatedTools() {
        let now = Date()
        var messages = [CoachChatMessage.user("Build me a split", at: now)]
        for _ in 0..<12 { messages.append(.tool("search_exercises", at: now)) }
        messages.append(.tool("get_profile", at: now))
        let entries = CoachChatTranscript.collapse(messages)
        #expect(entries.count == 3)
        if case .toolGroup(let label, let count, let failed) = entries[1] {
            #expect(label == CoachChatMessage.label(forTool: "search_exercises"))
            #expect(count == 12)
            #expect(!failed)
        } else {
            Issue.record("expected a collapsed tool group")
        }
        #expect(CoachChatTranscript.isWaitingForText(messages))
        messages.append(.assistant("", at: now))
        #expect(CoachChatTranscript.isWaitingForText(messages))
        messages[messages.count - 1].text = "Here's a plan."
        #expect(!CoachChatTranscript.isWaitingForText(messages))
    }
}
