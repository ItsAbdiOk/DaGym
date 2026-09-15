import Foundation

/// The contract between the coach model and the app: every tool the model may call, with the
/// schema its arguments must follow. GymCore owns the definitions so the wire format, the
/// executor and the tests all read one list; the app implements each name against the store.
///
/// Read tools return compact JSON the model quotes from; `propose_*` tools build a
/// `CoachChatDraft` the lifter applies or discards — the model never edits data directly. The
/// argument shapes of the `propose_*` tools are the Codable proposal types in
/// `CoachChatDraft.swift` (snake_case keys), so an executor decodes the arguments straight
/// into them.
public enum CoachChatToolCatalog {
    /// What the drafter (the conversation model) is offered.
    public static let tools: [CoachChatTool] = readTools + proposalTools

    /// What the second-opinion model is offered: the same reads and proposals, plus
    /// `agree_with_proposal`. The drafter never sees the agree tool.
    public static let reviewerTools: [CoachChatTool] = readTools + proposalTools + [agreeTool]

    /// Every tool either model can call, each once.
    public static let allTools: [CoachChatTool] = tools + [agreeTool]

    public static var names: [String] { tools.map(\.name) }

    public static func tool(named name: String) -> CoachChatTool? {
        allTools.first { $0.name == name }
    }

    // MARK: - Limits the schemas advertise (the executor enforces the same numbers)

    public static let maxRecentWorkouts = 30
    public static let defaultRecentWorkouts = 10
    public static let weeksRange = 1...26
    public static let defaultWeeks = 4
    public static let maxSearchResults = 60

    // MARK: - Shared fragments

    static let exerciseIDField = CoachChatToolSchema.string(
        "Exercise id (UUID) from search_exercises, get_routine or get_exercise_history. Prefer this "
            + "over exercise_name."
    )
    static let exerciseNameField = CoachChatToolSchema.string(
        "Exact exercise name from the library, used when the id is not known."
    )
    static let weeksField = CoachChatToolSchema.integer(
        "Calendar weeks to look back, most recent first. Default \(defaultWeeks).", in: weeksRange
    )

    // MARK: - Read tools

    static let readTools: [CoachChatTool] = [
        CoachChatTool(
            name: .getProfile,
            description: "The lifter's units, weekly session goal, latest bodyweight, training goal, "
                + "experience, equipment profile (equipment kinds and the specific machines available) "
                + "and active program. Call once before proposing anything.",
            parameters: .object(properties: [:])
        ),
        CoachChatTool(
            name: .listRoutines,
            description: "Every saved routine: id, name, exercise count, muscles trained, last performed.",
            parameters: .object(properties: [:])
        ),
        CoachChatTool(
            name: .getRoutine,
            description: "One routine in full: ordered exercises with planned sets (kind, reps, weight, "
                + "RPE), rest, supersets and the progression rule.",
            parameters: .object(
                properties: ["routine_id": .string("Routine id from list_routines.")],
                required: ["routine_id"]
            )
        ),
        CoachChatTool(
            name: .getSchedule,
            description: "The weekly schedule: which routine is planned on which weekday, plus "
                + "date-specific overrides for the next two weeks.",
            parameters: .object(properties: [:])
        ),
        CoachChatTool(
            name: .getRecentWorkouts,
            description: "The most recent logged workouts, newest first: id, date, routine, duration, "
                + "sets, volume. At most \(maxRecentWorkouts).",
            parameters: .object(properties: [
                "limit": .integer(
                    "How many to return. Default \(defaultRecentWorkouts).", in: 1...maxRecentWorkouts
                )
            ])
        ),
        CoachChatTool(
            name: .getWorkout,
            description: "One logged workout in full: every exercise and set with weight, reps, kind "
                + "and RPE.",
            parameters: .object(
                properties: ["workout_id": .string("Workout id from get_recent_workouts.")],
                required: ["workout_id"]
            )
        ),
        CoachChatTool(
            name: .getExerciseHistory,
            description: "One exercise's dated sessions (sets with weight and reps), the best estimated "
                + "1RM per session, and a 12-week summary. Use for 'how is my X going'.",
            parameters: .object(
                properties: ["exercise_id": exerciseIDField, "exercise_name": exerciseNameField]
            )
        ),
        CoachChatTool(
            name: .forecastE1RM,
            description: "When the lifter's estimated 1RM on an exercise is likely to reach a target, "
                + "from a weighted trend over the last 12 weeks. Always report the caveat it returns.",
            parameters: .object(
                properties: [
                    "exercise_id": exerciseIDField,
                    "exercise_name": exerciseNameField,
                    "target_kg": .number("Target estimated 1RM in kg.", in: 1...TrainingConstants.maxLoadKg)
                ],
                required: ["target_kg"]
            )
        ),
        CoachChatTool(
            name: .getWeeklyVolume,
            description: "Per calendar week: sessions, total sets, total volume (kg) and time trained.",
            parameters: .object(properties: ["weeks": weeksField])
        ),
        CoachChatTool(
            name: .getMuscleVolume,
            description: "Hard sets per muscle per week (primary mover 1, secondary 0.5) against the "
                + "app's own coverage floor, so you can say which muscles are under-trained.",
            parameters: .object(properties: ["weeks": weeksField])
        ),
        CoachChatTool(
            name: .getPersonalRecords,
            description: "Best set, best estimated 1RM and best volume per exercise, with dates. "
                + "Optionally for one exercise.",
            parameters: .object(
                properties: ["exercise_id": exerciseIDField, "exercise_name": exerciseNameField]
            )
        ),
        CoachChatTool(
            name: .getAdherence,
            description: "Planned versus completed sessions per week against the schedule, and the "
                + "current streak.",
            parameters: .object(properties: ["weeks": weeksField])
        ),
        CoachChatTool(
            name: .getRecovery,
            description: "How spent each muscle is right now (0 fresh … 1 fully spent) from recent "
                + "work, and which muscles are ready to train.",
            parameters: .object(properties: [:])
        ),
        CoachChatTool(
            name: .getBodyMeasurements,
            description: "Bodyweight and body measurements over time, newest first.",
            parameters: .object(properties: ["weeks": weeksField])
        ),
        CoachChatTool(
            name: .searchExercises,
            description: "List library exercises the lifter can do, filtered by primary muscle and/or "
                + "words from the name, optionally one equipment kind or machine. One call per muscle "
                + "group returns every allowed option for it — do not search one exercise at a time. "
                + "Not needed before propose_* tools, which accept exercise names and resolve them; "
                + "search when you want options or a name was rejected.",
            parameters: .object(
                properties: [
                    "muscle": .string(
                        "Primary muscle to list (preferred filter).", enum: Muscle.allCases.map(\.rawValue)
                    ),
                    "query": .string("Words from the name (e.g. 'row', 'incline'). Optional with muscle."),
                    "equipment": .string(
                        "Limit to one equipment kind.",
                        enum: ["barbell", "dumbbell", "machine", "cable", "bodyweight"]
                    ),
                    "machine": .string("Limit to one machine.", enum: Machine.allCases.map(\.rawValue)),
                    "allowed_only": .boolean("Only exercises the lifter's equipment allows (default true)."),
                    "limit": .integer("Most results to return (default 40).", in: 1...maxSearchResults)
                ]
            )
        )
    ]
}
