import Foundation
import Testing

@testable import GymCore

@Suite("CoachChatPrompt: the system prompt states the lifter's facts and the house rules")
struct CoachChatPromptTests {
    private let now = CoachTestSupport.date("2026-09-15T08:00:00Z")

    @Test("a full profile is stated line by line")
    func fullProfile() {
        let profile = LifterProfileFacts(
            unit: .lb, weeklyGoal: 4, bodyweightKg: 82.5, goal: .hypertrophy, experience: .intermediate,
            equipmentProfileName: "Home", equipmentTypes: ["dumbbell", "barbell"], machines: ["Pull-Up Bar"],
            restrictsMachines: true, activeProgramName: "Upper/Lower", routineNames: ["Upper", "Lower"],
            workoutsLast4Weeks: 13
        )
        let prompt = CoachChatPrompt.system(profile: profile, now: now, calendar: CoachTestSupport.calendar)
        #expect(prompt.hasPrefix("You are the coach inside DaGym"))
        #expect(prompt.contains("Today is Tuesday 2026-09-15."))
        #expect(prompt.contains("- Displays weights in lb."))
        #expect(prompt.contains("- Training for muscle, intermediate."))
        #expect(prompt.contains("- Aims for 4 sessions a week; 13 workouts in the last 4 weeks."))
        #expect(prompt.contains("- Bodyweight 182 lb."))
        #expect(prompt.contains("- Equipment (Home): barbell, dumbbell; only these stations: Pull-Up Bar."))
        #expect(prompt.contains("- Active program: Upper/Lower."))
        #expect(prompt.contains("- Routines: Upper, Lower."))
        for rule in CoachChatPrompt.houseRules {
            #expect(prompt.contains("- \(rule)"))
        }
    }

    @Test("a bare profile still gets the rules and asks about equipment")
    func bareProfile() {
        let prompt = CoachChatPrompt.system(
            profile: LifterProfileFacts(unit: .kg), now: now, calendar: CoachTestSupport.calendar
        )
        #expect(prompt.contains("- Equipment: not set; ask before proposing exercises."))
        #expect(!prompt.contains("Training for"))
        #expect(!prompt.contains("Routines:"))
        #expect(prompt.contains("Rules:"))
    }

    @Test("the house rules cover every promise the brief makes")
    func houseRules() {
        let rules = CoachChatPrompt.houseRules.joined(separator: " ")
        #expect(rules.contains("Always call tools for numbers"))
        #expect(rules.contains("which data you used"))
        #expect(rules.contains("propose_* tools"))
        #expect(rules.contains("equipment"))
        #expect(rules.contains("No headings"))
        #expect(rules.contains("one clarifying question"))
    }

    @Test("an unrestricted gym and a gym with no stations read differently")
    func equipmentLines() {
        let open = LifterProfileFacts(unit: .kg, equipmentTypes: ["machine", "cable"])
        #expect(
            CoachChatPrompt.equipmentLine(open) == "Equipment: cable, machine; every station of those kinds."
        )
        let none = LifterProfileFacts(unit: .kg, equipmentTypes: ["dumbbell"], restrictsMachines: true)
        #expect(
            CoachChatPrompt.equipmentLine(none) == "Equipment: dumbbell; no machines or stations at all."
        )
    }

    @Test("profile facts round-trip as JSON")
    func codable() throws {
        let profile = LifterProfileFacts(
            unit: .kg, weeklyGoal: 3, goal: .strength, equipmentTypes: ["barbell"]
        )
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(LifterProfileFacts.self, from: data) == profile)
    }
}
