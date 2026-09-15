import Foundation

/// The handful of facts about the lifter the system prompt states up front, so the model
/// knows the units, the goal and the gym before its first tool call. Built by the app from the
/// store and Preferences; everything else it needs comes through tools.
public struct LifterProfileFacts: Codable, Hashable, Sendable {
    public var unit: WeightUnit
    /// Sessions per week the lifter aims for.
    public var weeklyGoal: Int?
    public var bodyweightKg: Double?
    public var goal: TrainingGoal?
    public var experience: ExperienceLevel?
    public var equipmentProfileName: String?
    /// Equipment kinds the profile ticks ("barbell", "dumbbell", …).
    public var equipmentTypes: [String]
    /// Station display names the profile lists, when it restricts stations; empty when every
    /// station of the ticked kinds is assumed.
    public var machines: [String]
    public var restrictsMachines: Bool
    public var activeProgramName: String?
    public var routineNames: [String]
    public var workoutsLast4Weeks: Int?

    public init(
        unit: WeightUnit, weeklyGoal: Int? = nil, bodyweightKg: Double? = nil, goal: TrainingGoal? = nil,
        experience: ExperienceLevel? = nil, equipmentProfileName: String? = nil,
        equipmentTypes: [String] = [], machines: [String] = [], restrictsMachines: Bool = false,
        activeProgramName: String? = nil,
        routineNames: [String] = [], workoutsLast4Weeks: Int? = nil
    ) {
        self.unit = unit
        self.weeklyGoal = weeklyGoal
        self.bodyweightKg = bodyweightKg
        self.goal = goal
        self.experience = experience
        self.equipmentProfileName = equipmentProfileName
        self.equipmentTypes = equipmentTypes
        self.machines = machines
        self.restrictsMachines = restrictsMachines
        self.activeProgramName = activeProgramName
        self.routineNames = routineNames
        self.workoutsLast4Weeks = workoutsLast4Weeks
    }
}

/// The system prompt for the cloud coach. Pure text from `LifterProfileFacts` and the date;
/// the house rules are fixed so a test can pin the wording the model is held to.
public enum CoachChatPrompt {
    public static func system(profile: LifterProfileFacts, now: Date, calendar: Calendar) -> String {
        [
            identity,
            "Today is \(dateLine(now, calendar: calendar)).",
            "",
            "About the lifter:",
            profileLines(profile).map { "- \($0)" }.joined(separator: "\n"),
            "",
            "Rules:",
            houseRules.map { "- \($0)" }.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    static let identity = "You are the coach inside DaGym, an evidence-based strength coach. You have the "
        + "lifter's complete training log, routines, schedule, body measurements and equipment through tools."

    /// The wording the model is held to. Kept as separate lines so a test can check each one.
    public static let houseRules: [String] = [
        "Always call tools for numbers. Never guess or recall a weight, rep, date or set count; if you have "
            + "not read it this conversation, read it first.",
        "Say which data you used: name the exercise, the dates or the weeks the numbers come from.",
        "Propose changes only through the propose_* tools, never as prose or a list the lifter must type in. "
            + "The lifter reviews and applies every proposal; nothing you propose is saved on its own.",
        "Build routines from your own knowledge and propose them straight away by exercise name — the "
            + "app resolves names against its library and tells you if one is missing or not allowed. Do "
            + "not search for exercises one at a time; if you want to see options, call search_exercises "
            + "once per muscle group with the muscle filter, and make independent tool calls in the same "
            + "turn.",
        "Answer with one tool round where you can: read what you need together, then reply.",
        "Respect the lifter's equipment: only exercises search_exercises marks as allowed. Never suggest a "
            + "machine their gym does not have.",
        "Be concise. Plain language, short paragraphs, bullets where they help. No headings, no tables, no "
            + "markdown emphasis.",
        "Use the lifter's units in every number you write, and kg in every tool argument.",
        "If a request is ambiguous, ask one clarifying question instead of guessing.",
        "When a forecast or a tool returns a caveat, repeat it plainly; do not smooth it over.",
        "You are not a doctor. For pain or injury, advise seeing a professional and offer to work around it."
    ]

    static func profileLines(_ profile: LifterProfileFacts) -> [String] {
        var lines = ["Displays weights in \(profile.unit.symbol)."]
        if let goal = profile.goal {
            let experience = profile.experience.map { ", \($0.displayName.lowercased())" } ?? ""
            lines.append("Training for \(goal.displayName.lowercased())\(experience).")
        }
        if let weekly = profile.weeklyGoal {
            let recent = profile.workoutsLast4Weeks.map { "; \($0) workouts in the last 4 weeks" } ?? ""
            lines.append("Aims for \(weekly) sessions a week\(recent).")
        } else if let recent = profile.workoutsLast4Weeks {
            lines.append("\(recent) workouts in the last 4 weeks.")
        }
        if let bodyweight = profile.bodyweightKg {
            lines.append("Bodyweight \(profile.unit.format(kg: bodyweight)) \(profile.unit.symbol).")
        }
        lines.append(equipmentLine(profile))
        if let program = profile.activeProgramName { lines.append("Active program: \(program).") }
        if !profile.routineNames.isEmpty {
            lines.append("Routines: \(profile.routineNames.joined(separator: ", ")).")
        }
        return lines
    }

    static func equipmentLine(_ profile: LifterProfileFacts) -> String {
        let name = profile.equipmentProfileName.map { "Equipment (\($0)): " } ?? "Equipment: "
        guard !profile.equipmentTypes.isEmpty else {
            return name + "not set; ask before proposing exercises."
        }
        var line = name + profile.equipmentTypes.sorted().joined(separator: ", ")
        if profile.restrictsMachines {
            line += profile.machines.isEmpty
                ? "; no machines or stations at all"
                : "; only these stations: \(profile.machines.joined(separator: ", "))"
        } else {
            line += "; every station of those kinds"
        }
        return line + "."
    }

    /// "Tuesday 2026-09-15" — no locale, no wall clock, so the prompt is stable in a test.
    static func dateLine(_ now: Date, calendar: Calendar) -> String {
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: now))?.displayName ?? ""
        return "\(weekday) \(DateKey.string(for: now, calendar: calendar))"
    }
}
