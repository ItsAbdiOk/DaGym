import Foundation
import Testing
@testable import GymCore

@Suite("Progression rule")
struct ProgressionRuleTests {
    @Test("display names are short and rule-specific")
    func displayNames() {
        #expect(ProgressionRule.linear(incrementKg: 2.5).displayName == "Linear")
        #expect(ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 2.5).displayName
            == "Double progression")
        #expect(ProgressionRule.linearAMRAP(incrementKg: 2.5).displayName == "Linear + AMRAP")
        #expect(ProgressionRule.rpeBased(targetRPE: 8).displayName == "RPE-based")
        let percentRule = ProgressionRule.percentOfTrainingMax(scheme: .classic)
        #expect(percentRule.displayName == "Percentage / training max")
        #expect(ProgressionRule.bodyweight(repCeiling: 15, maxSets: 5).displayName == "Bodyweight")
        #expect(ProgressionRule.assisted(stepKg: 2.5).displayName == "Assisted")
        #expect(ProgressionRule.timed(stepSeconds: 5).displayName == "Timed")
    }

    @Test("every rule has a non-empty one-sentence explanation")
    func explanationsExist() {
        let rules: [ProgressionRule] = [
            .linear(incrementKg: 2.5),
            .doubleProgression(low: 8, high: 12, incrementKg: 2.5),
            .linearAMRAP(incrementKg: 2.5),
            .rpeBased(targetRPE: 8),
            .percentOfTrainingMax(scheme: .classic),
            .bodyweight(repCeiling: 15, maxSets: 5),
            .assisted(stepKg: 2.5),
            .timed(stepSeconds: 5)
        ]
        for rule in rules {
            #expect(!rule.explanation().isEmpty)
        }
    }

    @Test("explanation formats increments in the caller's unit")
    func explanationUnitAware() {
        let rule = ProgressionRule.linear(incrementKg: 2.5)
        #expect(rule.explanation(unit: .kg).contains("2.5 kg"))
        #expect(rule.explanation(unit: .lb).contains("lb"))
        #expect(!rule.explanation(unit: .lb).contains("kg"))
    }

    @Test("rules round-trip through Codable")
    func codable() throws {
        let rule = ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 2.5)
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ProgressionRule.self, from: data)
        #expect(decoded == rule)
    }

    @Test("the classic wave matches the plan.md §7 percentage table")
    func classicWaveMatchesPlan() {
        let week1 = WaveScheme.classic.weeks[1]
        #expect(week1?.map(\.percent) == [0.65, 0.75, 0.85])
        #expect(week1?.map(\.reps) == [5, 5, 5])
        #expect(week1?.map(\.isAMRAP) == [false, false, true])

        let week4 = WaveScheme.classic.weeks[4]
        #expect(week4?.map(\.percent) == [0.40, 0.50, 0.60])
        #expect(week4?.allSatisfy { !$0.isAMRAP } == true)
    }
}
