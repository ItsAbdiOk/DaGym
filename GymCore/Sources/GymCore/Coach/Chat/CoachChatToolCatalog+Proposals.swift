import Foundation

/// The five `propose_*` tools. Each schema mirrors its proposal type's coding keys exactly;
/// `CoachChatToolCatalogTests` decodes a schema-shaped argument object into the proposal so
/// the two cannot drift apart.
extension CoachChatToolCatalog {
    static let setSchema = CoachChatToolSchema.object(
        "One planned set.",
        properties: [
            "kind": .string(
                "Set kind. Default 'working'. Warm-ups never count toward progression.",
                enum: SetKind.allCases.map(\.rawValue)
            ),
            "target_reps": .integer("Reps to aim for.", in: CoachChatDraft.Limits.repsRange),
            "target_weight_kg": .number(
                "Working weight in kg. Omit for bodyweight or when the lifter has never done the exercise.",
                in: 0...CoachChatDraft.Limits.maxWeightKg
            ),
            "rpe": .number("Target RPE.", in: CoachChatDraft.Limits.rpeRange)
        ],
        required: ["target_reps"]
    )

    static let exerciseSchema = CoachChatToolSchema.object(
        "One exercise. Give exercise_name (or exercise_id). Prefer the shorthand set_count + "
            + "target_reps (+ target_reps_high for a range, target_weight_kg, rpe, warmup_sets); use "
            + "the `sets` array only when individual sets must differ.",
        properties: [
            "exercise_id": exerciseIDField,
            "exercise_name": exerciseNameField,
            "set_count": .integer("Working sets (shorthand).", in: CoachChatDraft.Limits.setsPerExercise),
            "target_reps": .integer("Reps per working set (shorthand).", in: CoachChatDraft.Limits.repsRange),
            "target_reps_high": .integer(
                "Top of a rep range, e.g. 8–12 → target_reps 8, target_reps_high 12.",
                in: CoachChatDraft.Limits.repsRange
            ),
            "target_weight_kg": .number(
                "Working weight in kg (shorthand). Omit for bodyweight or an exercise never done.",
                in: 0...CoachChatDraft.Limits.maxWeightKg
            ),
            "rpe": .number("Target RPE for working sets (shorthand).", in: CoachChatDraft.Limits.rpeRange),
            "warmup_sets": .integer("Warm-up sets before the working sets (shorthand).", in: 0...3),
            "sets": .array(
                "Explicit sets, \(CoachChatDraft.Limits.setsPerExercise.lowerBound)–"
                    + "\(CoachChatDraft.Limits.setsPerExercise.upperBound), when they differ.",
                of: setSchema
            ),
            "rest_seconds": .integer("Rest between sets.", in: CoachChatDraft.Limits.restSecondsRange),
            "superset_group": .integer("Exercises sharing a number are a superset.", in: 1...10),
            "reason": .string(
                "One short clause on why this exercise for this lifter, tied to their data "
                    + "(≤ \(CoachChatDraft.Limits.maxReasonLength) characters)."
            )
        ]
    )

    static let routineSchema = CoachChatToolSchema.object(
        "A routine: name, ordered exercises, optional progression rule and notes.",
        properties: [
            "name": .string("Short routine name, e.g. 'Upper A'."),
            "exercises": .array(
                "\(CoachChatDraft.Limits.exercisesPerRoutine.lowerBound)–"
                    + "\(CoachChatDraft.Limits.exercisesPerRoutine.upperBound) exercises in order.",
                of: exerciseSchema
            ),
            "rule": .string(
                "Progression rule for every exercise. Default is the app's per-exercise default.",
                enum: CoachChatRuleChoice.allCases.map(\.rawValue)
            ),
            "notes": .string("One or two sentences of coaching notes shown with the routine.")
        ],
        required: ["name", "exercises"]
    )

    static let proposalTools: [CoachChatTool] = [
        CoachChatTool(
            name: .proposeRoutine,
            description: "Propose a new routine for the lifter to review and save. Only exercises from "
                + "search_exercises that the lifter's equipment allows; each exercise once. Returns the "
                + "validated draft, or the list of problems to fix and call again.",
            parameters: routineSchema
        ),
        CoachChatTool(
            name: .proposeProgram,
            description: "Propose a multi-day program. Either give the routines in full, or leave them "
                + "out to use the app's own template for the goal, built from the lifter's equipment. "
                + "The lifter reviews it before anything is saved.",
            parameters: .object(properties: [
                "name": .string("Program name, e.g. 'Upper/Lower 4-day'."),
                "goal": .string("Training goal.", enum: TrainingGoal.allCases.map(\.rawValue)),
                "days_per_week": .integer("Training days per week.", in: ProgramRequest.daysRange),
                "experience": .string("Lifter's experience.", enum: ExperienceLevel.allCases.map(\.rawValue)),
                "session_minutes": .integer("Minutes per session.", in: ProgramRequest.sessionMinutesRange),
                "routines": .array("The program's routines, one per training day at most.", of: routineSchema)
            ], required: ["name", "goal", "days_per_week"])
        ),
        CoachChatTool(
            name: .proposeSchedule,
            description: "Propose which routine runs on which weekday. Days not listed become rest "
                + "days. Use routine ids from list_routines.",
            parameters: .object(properties: [
                "days": .object(
                    "Weekday to routine id.",
                    properties: Dictionary(
                        Weekday.allCases.map {
                            (
                                $0.displayName.lowercased(),
                                CoachChatToolSchema.string("Routine id for \($0.displayName).")
                            )
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                )
            ], required: ["days"])
        ),
        CoachChatTool(
            name: .proposeDeload,
            description: "Propose backing one exercise's working weight off by a percentage across "
                + "every routine that programs it. Cite the stall or fatigue data that justifies it.",
            parameters: .object(properties: [
                "exercise_id": exerciseIDField,
                "exercise_name": exerciseNameField,
                "percent": .number(
                    "Percent to drop the working weight by.", in: CoachChatDraft.Limits.deloadPercentRange
                )
            ], required: ["percent"])
        ),
        CoachChatTool(
            name: .proposeSwap,
            description: "Propose replacing one exercise in one routine with another, keeping its sets. "
                + "The replacement must be allowed by the lifter's equipment.",
            parameters: .object(properties: [
                "routine_id": .string("Routine id from list_routines."),
                "from_exercise_id": exerciseIDField,
                "from_exercise_name": exerciseNameField,
                "to_exercise_id": exerciseIDField,
                "to_exercise_name": exerciseNameField
            ], required: ["routine_id"])
        )
    ]

    /// The reviewer's other verdict. Its arguments are `CoachChatAgreement`.
    static let agreeTool = CoachChatTool(
        name: .agreeWithProposal,
        description: "Agree that the other coach's proposal is sound as it stands. Give the reasons "
            + "you checked it against — the lifter reads them. Call this or a propose_* tool, never both.",
        parameters: .object(properties: [
            "reasons": .array(
                "\(CoachChatAgreement.reasonsRange.lowerBound)–\(CoachChatAgreement.reasonsRange.upperBound) "
                    + "short lines, each one thing you checked and why it holds.",
                of: .string("One reason, under \(CoachChatAgreement.maxReasonLength) characters.")
            ),
            "confidence": .string(
                "How sure you are.", enum: CoachChatAgreement.Confidence.allCases.map(\.rawValue)
            )
        ], required: ["reasons", "confidence"])
    )
}
