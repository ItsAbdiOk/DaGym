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
    /// A few allowed exercise names per primary muscle (the ones the lifter has done, then
    /// favourites, then the library's classics), so the model can propose without searching.
    public var libraryByMuscle: [String: [String]] = [:]

    public init(
        unit: WeightUnit, weeklyGoal: Int? = nil, bodyweightKg: Double? = nil, goal: TrainingGoal? = nil,
        experience: ExperienceLevel? = nil, equipmentProfileName: String? = nil,
        equipmentTypes: [String] = [], machines: [String] = [], restrictsMachines: Bool = false,
        activeProgramName: String? = nil,
        routineNames: [String] = [], workoutsLast4Weeks: Int? = nil,
        libraryByMuscle: [String: [String]] = [:]
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
        self.libraryByMuscle = libraryByMuscle
    }
}

/// The system prompt for the cloud coach. Pure text from `LifterProfileFacts` and the date;
/// the house rules are fixed so a test can pin the wording the model is held to.
public enum CoachChatPrompt {
    /// Facts printed in the "What you remember" block at most; older ones stay behind `recall`.
    public static let maxMemoryLines = 15

    public static func system(
        profile: LifterProfileFacts, memory: [CoachMemoryFact] = [], now: Date, calendar: Calendar
    ) -> String {
        [
            identity,
            "Today is \(dateLine(now, calendar: calendar)).",
            "",
            "About the lifter:",
            profileLines(profile).map { "- \($0)" }.joined(separator: "\n"),
            libraryBlock(profile),
            memoryBlock(memory, calendar: calendar),
            "How you coach:",
            coachingPrinciples.map { "- \($0)" }.joined(separator: "\n"),
            "",
            "Reading the data (which tool answers what):",
            dataGuide.map { "- \($0)" }.joined(separator: "\n"),
            "",
            "Rules:",
            houseRules.map { "- \($0)" }.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    /// The addendum the second-opinion model gets on top of `system`: it is judging another
    /// coach's proposal for this lifter, and must either agree or put up its own.
    public static func reviewerAddendum(drafterName: String) -> String {
        """

        Your role in this turn: you are the second coach. \(drafterName) has read the same data and \
        proposed the plan below for the lifter's request. Check it the way a head coach checks an \
        assistant's programme: exercise selection for the lifter's days and equipment, volume per muscle \
        against what they have been recovering from, progression and rep targets against their history, \
        starting weights against their recent working weights, and whether it actually answers what \
        they asked. Read whatever data you need first. Then do exactly one of two things: call \
        agree_with_proposal with the reasons it is sound (name the two or three things you checked), or \
        call the matching propose_* tool with your own version and say, in one short paragraph, what you \
        changed and why. Do not both agree and propose. Do not rewrite for taste — change only what the \
        data or the lifter's constraints justify.
        """
    }

    static let identity = "You are the lifter's personal strength coach inside DaGym. You have their "
        + "complete training log, routines, schedule, body measurements, recovery and equipment through "
        + "tools, and you know them the way a coach who has watched every session does. You are "
        + "evidence-based, direct and warm; you programme like a coach, not a content generator."

    /// The coaching model the prompt holds the model to. Separate lines so tests can pin them.
    public static let coachingPrinciples: [String] = [
        "Coach the person in front of you: their goal, days available, session length, equipment, "
            + "experience and what their log says they actually do — not a template.",
        "Programme by yield. With few sessions, choose compound lifts and movements that cover a "
            + "whole muscle (overhead press plus lateral raises for all three delts; rows and pulldowns "
            + "for the back) before isolation. With more sessions, add isolation for lagging muscles and "
            + "spread volume across the week so each muscle gets two exposures where possible.",
        "Volume and intensity from their history, not from a chart: read get_muscle_volume and "
            + "get_weekly_volume for what they have been doing and recovering from, and change it in "
            + "steps (roughly ±2 to 4 sets per muscle per week), never a jump.",
        "Fatigue is part of the plan. Read get_recovery before proposing a session or a change: a "
            + "muscle still recovering gets lighter or later work; several red muscles, falling e1RMs, "
            + "missed sessions or a long streak of hard weeks are deload signals — propose_deload or "
            + "an easier week rather than piling on. An easier week is one change: a single "
            + "propose_deload (or one schedule change) covering the tired muscles, not a card per "
            + "exercise plus a new routine.",
        "Progression is week on week. Compare this week to the last few (get_exercise_history, "
            + "get_recent_workouts): reps up at the same load, or load up at the same reps, is progress; "
            + "two or three stalls at a weight is a cue to change the rep target, the exercise, or "
            + "deload — say which and why.",
        "Set target weights from the lifter's own numbers: call get_exercise_history for the exercise, "
            + "or for the closest exercise on the same primary muscle and equipment, and start 5–10% "
            + "under the best recent working weight — never equal to it, even for a lift they are "
            + "already doing (a new plan starts a little easier and progresses). When there is no "
            + "history at all, omit the weight rather than guess one.",
        "Rep targets follow the goal: strength mostly 3–6, muscle mostly 6–12 with some 12–20 for "
            + "isolation, and rest long enough to repeat the effort (2–3 min compounds, 60–90 s "
            + "isolation). Beginners get fewer exercises done well; advanced lifters get more specific "
            + "work.",
        "Adherence beats optimal: a plan they will do on their days, in their time, with their kit, "
            + "wins. If they train less than they aim to, programme for the sessions they actually make "
            + "and say so.",
        "When reviewing an existing plan, coach in tweaks — a set, a rep target, one swap, a deload — "
            + "through the propose_* tools, not a rewrite, unless they ask for a new plan or the data "
            + "says the plan is wrong for them.",
        "Explain like a coach: for each exercise or change, one line of why, tied to their data "
            + "(the lift, the dates, the numbers). No lectures. In a proposed routine, put that line in "
            + "each exercise's `reason` so it shows on the card."
    ]

    /// What each read tool is for, so the model reaches for the right one first.
    public static let dataGuide: [String] = [
        "get_profile: goal, units, bodyweight, equipment and machines, active program, routines.",
        "list_routines / get_routine: the plans as they are, with every set and target.",
        "get_schedule: which routine is planned on which day.",
        "get_recent_workouts / get_workout: what actually happened, session by session.",
        "get_exercise_history: every set of one lift with best e1RM per session — the source for "
            + "weights, rep targets and stalls; forecast_e1rm: when a target is reachable at the current "
            + "trend.",
        "get_weekly_volume / get_muscle_volume: sets and tonnage per week and per muscle, against the "
            + "app's coverage thresholds — the source for volume decisions.",
        "get_recovery: how recovered each muscle is right now; get_adherence: planned versus done; "
            + "get_personal_records: bests; get_body_measurements: bodyweight and measurements over time.",
        "search_exercises: the library by muscle or name, marked allowed or not for their equipment."
    ]

    /// Exercise names the lifter can do, by muscle — enough to write a routine straight from the
    /// prompt. Just the blank line when the profile carries none (search_exercises still works).
    static func libraryBlock(_ profile: LifterProfileFacts) -> String {
        guard !profile.libraryByMuscle.isEmpty else { return "" }
        let lines = profile.libraryByMuscle.keys.sorted().compactMap { muscle -> String? in
            guard let names = profile.libraryByMuscle[muscle], !names.isEmpty else { return nil }
            return "- \(muscle): \(names.joined(separator: ", "))"
        }
        return "\nExercises the lifter can do, by primary muscle (use these names in proposals; the full "
            + "library is available through search_exercises):\n" + lines.joined(separator: "\n") + "\n"
    }

    /// What the coach was told to keep in mind, most recent first, at most `maxMemoryLines`
    /// — "- [injury, 2026-09-01] Knees hurt on leg press." The blank string when there is
    /// nothing, so the prompt reads the same as before memory existed.
    public static func memoryBlock(_ facts: [CoachMemoryFact], calendar: Calendar) -> String {
        guard !facts.isEmpty else { return "" }
        let recent = facts.sorted { $0.createdAt > $1.createdAt }.prefix(maxMemoryLines)
        let lines = recent.map { fact in
            let stamp = DateKey.string(for: fact.createdAt, calendar: calendar)
            let until = fact.expiresAt.map { ", until \(DateKey.string(for: $0, calendar: calendar))" } ?? ""
            return "- [\(fact.topic.rawValue), \(stamp)\(until)] \(fact.text)"
        }
        let more = facts.count > recent.count
            ? "\n(\(facts.count - recent.count) older facts are available through recall.)" : ""
        return "\nWhat you remember from earlier chats (the lifter can edit this list in Settings):\n"
            + lines.joined(separator: "\n") + more + "\n"
    }

    /// The wording the model is held to. Kept as separate lines so a test can check each one.
    public static let houseRules: [String] = [
        "When the lifter states a durable fact — an injury or pain, an exercise they hate or love, a "
            + "schedule change, an equipment change, a new goal — call remember once with it, so the "
            + "next chat knows. Never remember weights, sets, reps or what happened in a session: the "
            + "log has those and the tools read them.",
        "Always call tools for numbers. Never guess or recall a weight, rep, date or set count; if you have "
            + "not read it this conversation, read it first.",
        "Say which data you used: name the exercise, the dates or the weeks the numbers come from.",
        "Propose changes only through the propose_* tools, never as prose or a list the lifter must type in. "
            + "The lifter reviews and applies every proposal; nothing you propose is saved on its own. "
            + "Advice like 'drop a set' or 'take 5% off' that is not inside a propose_* call is a failed "
            + "turn: if you recommend a change, make the call in the same turn. Never end with "
            + "'would you like me to update…?' — the card is the question, and it has a Discard "
            + "button.",
        "Build routines from your own knowledge and propose them straight away by exercise name — the "
            + "app resolves names against its library and tells you if one is missing or not allowed. Do "
            + "not search for exercises one at a time; if you want to see options, call search_exercises "
            + "once per muscle group with the muscle filter, and make independent tool calls in the same "
            + "turn.",
        "Read everything a proposal depends on before you make it — recovery, recent sessions, the "
            + "history of the lifts you will program — and batch independent reads in one turn. "
            + "Thoroughness beats speed; the lifter sees each step.",
        "Respect the lifter's equipment: only exercises search_exercises marks as allowed. Never suggest a "
            + "machine their gym does not have.",
        "Be concise. Plain language, short paragraphs. Light markdown only: **bold** for the one number "
            + "that matters, numbered or bulleted lists where they help. No headings, no tables.",
        "Quote spans as you read them: eight weeks of history is eight weeks, not twelve; three stalled "
            + "sessions is three. Never round a timeframe up or invent one.",
        "Use the lifter's units in every number you write, and kg in every tool argument.",
        "Do not ask clarifying questions when a sensible reading exists: state the assumption in one line "
            + "and proceed. 'Make me a routine' is enough to act on — take the goal, days and equipment "
            + "from the profile, pick the split that fits them, and propose it; they can ask for changes. "
            + "Ask only when you genuinely cannot act without the answer.",
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
