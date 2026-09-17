import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("Coach chat screen: header, opening bubble and tool trail")
struct CoachChatOpeningTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private func usage(cost: Double) -> OpenRouterWire.Usage {
        OpenRouterWire.Usage(promptTokens: 1_000, completionTokens: 500, totalTokens: nil, cost: cost)
    }

    private func spend(_ ledger: CoachChatUsageLedger, now: Date) -> String {
        CoachChatOpening.spendLine(ledger: ledger, now: now, calendar: calendar)
    }

    @Test("an empty ledger says $0.00 this month; a review due leads with Weekly review")
    func subtitleEmpty() {
        let now = date(2026, 9, 17)
        let ledger = CoachChatUsageLedger()
        #expect(
            CoachChatOpening.subtitle(reviewDue: true, ledger: ledger, now: now, calendar: calendar)
                == "Weekly review · $0.00 this month"
        )
        #expect(
            CoachChatOpening.subtitle(reviewDue: false, ledger: ledger, now: now, calendar: calendar)
                == "$0.00 this month"
        )
    }

    @Test("spend counted from this month says this month; from an earlier month says since <month>")
    func subtitleSpend() {
        let now = date(2026, 9, 17)
        var ledger = CoachChatUsageLedger()
        ledger.record(usage(cost: 0.14), model: "x", at: date(2026, 9, 2))
        #expect(spend(ledger, now: now) == "$0.14 this month")
        var older = CoachChatUsageLedger()
        older.record(usage(cost: 0.14), model: "x", at: date(2026, 6, 2))
        #expect(spend(older, now: now) == "$0.14 since Jun")
    }

    @Test("the opening bubble reads the recap and asks for the review only when one is due")
    func openingLine() {
        var recap = WeeklyRecap(
            weekStart: Date(), weeklyGoal: 4, workouts: 3, sets: 40, volumeKg: 47_200, prs: 1,
            workoutsDelta: 0, setsDelta: 0, prsDelta: 0, volumeDeltaPercent: nil
        )
        let volume = "47,200 kg"
        #expect(
            CoachChatOpening.line(recap: recap, reviewDue: true, volume: volume)
                == "Your week is done: 3 of 4 sessions, 47,200 kg of volume, one PR. Want the review?"
        )
        recap.prs = 0
        #expect(
            CoachChatOpening.line(recap: recap, reviewDue: false, volume: volume)
                == "Your week so far: 3 of 4 sessions, 47,200 kg of volume, no PRs. "
                + "What would you like to look at?"
        )
        recap.workouts = 0
        let empty = CoachChatOpening.line(recap: recap, reviewDue: false, volume: "0 kg")
        #expect(empty.hasPrefix("Nothing logged"))
    }

    @Test("Review my week leads the chips only when a review is due")
    func chips() {
        #expect(CoachChatOpening.chips(reviewDue: false) == CoachChatSuggestedPrompts.all)
        #expect(CoachChatOpening.chips(reviewDue: true).first == CoachChatOpening.reviewChip)
        #expect(CoachChatOpening.chips(reviewDue: true).count == 4)
    }

    @Test("consecutive tool groups become one trail block with a line per group")
    func trailBlocks() {
        let now = Date()
        var messages = [CoachChatMessage.user("Build me a split", at: now)]
        messages.append(.tool("get_profile", at: now))
        for _ in 0..<3 { messages.append(.tool("search_exercises", at: now)) }
        messages.append(.assistant("Here's a plan.", at: now))
        let blocks = CoachChatTranscript.blocks(messages)
        #expect(blocks.count == 3)
        if case .trail(let lines) = blocks[1] {
            #expect(lines.count == 2)
            #expect(lines[1].count == 3)
            #expect(lines[1].text.hasSuffix("×3"))
        } else {
            Issue.record("expected a tool trail")
        }
    }
}

@Suite("Insights card copy")
struct CoachCardCopyTests {
    @Test("every rule has a kicker and only real actions get a concrete button label")
    func kickersAndLabels() {
        for rule in CoachRule.allCases {
            #expect(CoachCardCopy.kicker(for: rule) != "Insight")
        }
        let weight = { (kg: Double) in "\(Int(kg)) kg" }
        let deload = CoachSuggestedAction.deloadExercise(
            exerciseName: "Bench", exerciseID: UUID(), toWeightKg: 60
        )
        #expect(CoachCardCopy.primaryLabel(for: deload, formatWeight: weight) == "Deload to 60 kg")
        #expect(CoachCardCopy.primaryLabel(for: .restMuscle(.chest), formatWeight: weight) == "Approve")
        #expect(CoachCardCopy.primaryLabel(for: .none, formatWeight: weight) == "Got it")
        #expect(CoachCardCopy.actionNote(for: .none, formatWeight: weight) == nil)
        let rest = CoachCardCopy.actionNote(for: .restMuscle(.chest), formatWeight: weight)
        #expect(rest?.hasPrefix("Approve just") == true)
    }
}
