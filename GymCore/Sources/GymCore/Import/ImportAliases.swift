import Foundation

/// A curated map from the ~40 most common third-party export exercise names to our own seed
/// exercise ids (`DaGym/Resources/Seed/exercises.json`), consulted by `WorkoutImportService`
/// before fuzzy matching. Built entirely from our own seed list — never from another app's alias
/// table (LICENCE: OpenGym is AGPL, we're MIT).
///
/// Hevy commonly qualifies a name with its equipment, e.g. "Bench Press (Barbell)" or "Squat
/// (Dumbbell)"; an unqualified name ("Squat", bare "Bicep Curl") resolves to the barbell variant
/// when one exists, matching how most lifters read an unqualified name.
public enum ImportAliases {
    /// The seed exercise id for `name`, or `nil` when it isn't one of the curated common names.
    ///
    /// A name that *names its equipment* is only ever answered with that equipment's variant:
    /// "Squat (Bodyweight)", "Deadlift (Dumbbell)" and "Bicep Curl (Cable)" have no entry here, so
    /// they fall through to fuzzy matching (and, failing that, a custom exercise) rather than
    /// collapsing onto the barbell seed — which would merge a different lift's history into the
    /// barbell one and hand it the barbell's personal records. Only an *unqualified* name ("Squat",
    /// bare "Bicep Curl") takes the barbell default, which is how most lifters read it.
    public static func seedID(for name: String) -> String? {
        let (base, qualifier) = normalised(name)
        guard let entry = table[base] else { return nil }
        if let qualifier { return entry[qualifier] }
        if let barbell = entry["barbell"] { return barbell }
        return entry.keys.min().flatMap { entry[$0] }
    }

    /// Splits a trailing "(Barbell)"/"(Dumbbell)"/... qualifier off the name, lower-cased.
    private static func normalised(_ name: String) -> (base: String, qualifier: String?) {
        var text = name.trimmingCharacters(in: .whitespaces)
        guard let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else {
            return (text.lowercased(), nil)
        }
        let inside = text[text.index(after: open)..<close]
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard knownQualifiers.contains(inside) else {
            return (text.lowercased(), nil)
        }
        text = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        return (text.lowercased(), canonicalQualifier(inside))
    }

    /// Folds spelling variants of the same equipment onto the key the table uses, so
    /// "(EZ Bar)" and "(EZ-Bar)" both find the `ezbar` entry.
    private static func canonicalQualifier(_ qualifier: String) -> String {
        switch qualifier {
        case "ez bar", "ez-bar": "ezbar"
        case "smith machine": "smith"
        default: qualifier
        }
    }

    private static let knownQualifiers: Set<String> = [
        "barbell", "dumbbell", "machine", "cable", "kettlebell", "bodyweight", "ezbar", "ez bar",
        "ez-bar", "smith", "smith machine", "band", "assisted", "weighted"
    ]

    /// normalised(unqualified name) → equipment qualifier → seed id.
    private static let table: [String: [String: String]] = [
        "squat": ["barbell": "Barbell_Squat"],
        "back squat": ["barbell": "Barbell_Squat"],
        "goblet squat": ["dumbbell": "Dumbbell_Goblet_Squat", "kettlebell": "Goblet_Squat"],
        "deadlift": ["barbell": "Barbell_Deadlift"],
        "romanian deadlift": ["barbell": "Romanian_Deadlift", "dumbbell": "Dumbbell_Romanian_Deadlift"],
        "rdl": ["barbell": "Romanian_Deadlift"],
        "sumo deadlift": ["barbell": "Sumo_Deadlift"],
        "bench press": ["barbell": "Barbell_Bench_Press_-_Medium_Grip", "dumbbell": "Dumbbell_Bench_Press"],
        "incline bench press": [
            "barbell": "Barbell_Incline_Bench_Press_-_Medium_Grip",
            "dumbbell": "Incline_Bench_Press_Dumbbell", "smith": "Smith_Machine_Incline_Bench_Press"
        ],
        "overhead press": ["barbell": "Standing_Military_Press"],
        "military press": ["barbell": "Standing_Military_Press"],
        "ohp": ["barbell": "Standing_Military_Press"],
        "shoulder press": [
            "barbell": "Barbell_Shoulder_Press", "dumbbell": "Dumbbell_Shoulder_Press",
            "machine": "Machine_Shoulder_Military_Press"
        ],
        "lat pulldown": ["cable": "Wide-Grip_Lat_Pulldown", "machine": "Wide-Grip_Lat_Pulldown"],
        "pulldown": ["cable": "Wide-Grip_Lat_Pulldown"],
        "barbell row": ["barbell": "Bent_Over_Barbell_Row"],
        "bent over row": ["barbell": "Bent_Over_Barbell_Row"],
        "dumbbell row": ["dumbbell": "One-Arm_Dumbbell_Row"],
        "bicep curl": ["barbell": "Barbell_Curl", "dumbbell": "Dumbbell_Bicep_Curl"],
        "biceps curl": ["barbell": "Barbell_Curl", "dumbbell": "Dumbbell_Bicep_Curl"],
        "curl": ["barbell": "Barbell_Curl", "dumbbell": "Dumbbell_Curl"],
        "hammer curl": ["dumbbell": "Hammer_Curls"],
        "hip thrust": ["barbell": "Barbell_Hip_Thrust", "dumbbell": "Dumbbell_Hip_Thrust"],
        "leg press": ["machine": "Leg_Press"],
        "leg extension": ["machine": "Leg_Extensions"],
        "leg curl": ["machine": "Lying_Leg_Curls"],
        "pull up": ["bodyweight": "Pullups", "assisted": "Assisted_Pull_Up"],
        "pull-up": ["bodyweight": "Pullups"],
        "pullup": ["bodyweight": "Pullups"],
        "chin up": ["bodyweight": "Chin-Up"],
        "chin-up": ["bodyweight": "Chin-Up"],
        "push up": ["bodyweight": "Push_Up"],
        "push-up": ["bodyweight": "Push_Up"],
        "shrug": ["barbell": "Barbell_Shrug", "dumbbell": "Dumbbell_Shrug"],
        "lateral raise": ["dumbbell": "Side_Lateral_Raise", "cable": "Side_Lateral_Raise_Cable"],
        "side lateral raise": ["dumbbell": "Side_Lateral_Raise"],
        "tricep pushdown": ["cable": "Triceps_Pushdown"],
        "triceps pushdown": ["cable": "Triceps_Pushdown"],
        "skull crusher": ["ezbar": "EZ-Bar_Skullcrusher"],
        "skullcrusher": ["ezbar": "EZ-Bar_Skullcrusher"],
        "cable row": ["cable": "Seated_Cable_Row"],
        "seated row": ["cable": "Seated_Cable_Row"],
        "face pull": ["cable": "Face_Pull"],
        // Strong's machine/cable catalogue names, as they appear in a real 2026 export.
        "cable crossover": ["cable": "Cable_Crossover"],
        "chest press": ["machine": "Leverage_Chest_Press", "cable": "Cable_Chest_Press"],
        "incline chest press": ["machine": "Leverage_Incline_Chest_Press"],
        "iso-lateral row": ["machine": "Leverage_Iso_Row"],
        "pec deck": ["machine": "Pec_Deck"],
        "preacher curl": [
            "machine": "Machine_Preacher_Curls", "barbell": "Preacher_Curl", "cable": "Cable_Preacher_Curl"
        ],
        "reverse fly": ["machine": "Reverse_Machine_Flyes", "dumbbell": "Reverse_Flyes"],
        "seated dips": ["machine": "Dip_Machine"],
        "seated wide-grip row": ["cable": "Seated_Cable_Row"],
        // Strong spells the attachment inside the qualifier, which `normalised` leaves in the base.
        "triceps pushdown (cable - straight bar)": ["cable": "Triceps_Pushdown"],
        "triceps pushdown (cable - rope)": ["cable": "Triceps_Pushdown_-_Rope_Attachment"],
        "triceps pushdown (cable - v-bar)": ["cable": "Triceps_Pushdown_-_V-Bar_Attachment"]
    ]
}
