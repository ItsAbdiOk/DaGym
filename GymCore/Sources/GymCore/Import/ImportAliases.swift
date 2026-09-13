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
    public static func seedID(for name: String) -> String? {
        let (base, qualifier) = normalised(name)
        guard let entry = table[base] else { return nil }
        if let qualifier, let id = entry[qualifier] { return id }
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
        return (text.lowercased(), inside)
    }

    private static let knownQualifiers: Set<String> = [
        "barbell", "dumbbell", "machine", "cable", "kettlebell", "bodyweight", "ezbar", "ez bar"
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
            "barbell": "Barbell_Incline_Bench_Press_-_Medium_Grip", "dumbbell": "Incline_Bench_Press_Dumbbell"
        ],
        "overhead press": ["barbell": "Standing_Military_Press"],
        "military press": ["barbell": "Standing_Military_Press"],
        "ohp": ["barbell": "Standing_Military_Press"],
        "shoulder press": ["barbell": "Barbell_Shoulder_Press", "dumbbell": "Dumbbell_Shoulder_Press"],
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
        "pull up": ["bodyweight": "Pullups"],
        "pull-up": ["bodyweight": "Pullups"],
        "pullup": ["bodyweight": "Pullups"],
        "chin up": ["bodyweight": "Chin-Up"],
        "chin-up": ["bodyweight": "Chin-Up"],
        "push up": ["bodyweight": "Push_Up"],
        "push-up": ["bodyweight": "Push_Up"],
        "shrug": ["barbell": "Barbell_Shrug", "dumbbell": "Dumbbell_Shrug"],
        "lateral raise": ["dumbbell": "Side_Lateral_Raise"],
        "side lateral raise": ["dumbbell": "Side_Lateral_Raise"],
        "tricep pushdown": ["cable": "Triceps_Pushdown"],
        "triceps pushdown": ["cable": "Triceps_Pushdown"],
        "skull crusher": ["ezbar": "EZ-Bar_Skullcrusher"],
        "skullcrusher": ["ezbar": "EZ-Bar_Skullcrusher"],
        "cable row": ["cable": "Seated_Cable_Row"],
        "seated row": ["cable": "Seated_Cable_Row"],
        "face pull": ["cable": "Face_Pull"]
    ]
}
