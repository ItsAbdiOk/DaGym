import Foundation

/// The per-station catalogue: the labels a floor (Matrix / Technogym / Precor / Life Fitness /
/// Hammer Strength, as at PureGym) prints on the machine, so a search for what the lifter
/// *calls* it finds the station; and a bundled, public-domain photograph that shows it.
extension Machine {
    /// Names a lifter would use for this station besides `displayName` — the labels on the
    /// machine itself across the common brands plus UK gym-floor slang. Searched
    /// case-insensitively by `matches(_:)`. No alias may repeat across stations, and none is a
    /// substring of the station's own `displayName` (both tested): such an alias adds nothing
    /// to search but used to take one of the two hint slots the profile editor shows.
    public var aliases: [String] {
        switch self {
        case .legPress, .hackSquat, .pendulumSquat, .beltSquat, .smithMachine: legAliases
        case .pecDeck, .chestPressMachine, .shoulderPressMachine, .lateralRaiseMachine, .pulloverMachine:
            pressAliases
        case .legCurl, .legExtension, .hipAbductorAdductor, .multiHip, .gluteKickback: hipAliases
        case .calfRaiseMachine, .seatedCalf, .abCrunchMachine, .torsoRotation, .backExtension,
             .gluteHamDeveloper:
            trunkAliases
        case .assistedDipPullUp, .preacherCurlMachine, .tricepsExtensionMachine, .seatedDipMachine,
             .rowMachine:
            armAliases
        case .latPulldown, .seatedRowMachine, .cableStation, .pullUpBar, .dipStation: cableAliases
        case .treadmill, .stationaryBike, .elliptical, .rower, .stairClimber, .skiErg: cardioAliases
        }
    }

    private var legAliases: [String] {
        switch self {
        case .legPress: [
            "45° Leg Press", "Seated Leg Press", "Linear Leg Press", "Leg Press Machine",
            "Horizontal Leg Press", "Vertical Leg Press", "Plate-Loaded Leg Press",
            "Iso-Lateral Leg Press", "Sled Leg Press", "Leg Press / Calf Press", "Leg Sled"
        ]
        case .hackSquat: [
            "Linear Hack Squat", "Hack Squat Machine", "V-Squat", "V-Squat Machine", "Hack Press",
            "Squat Machine", "Reverse Hack Squat", "Plate-Loaded Hack Squat"
        ]
        case .pendulumSquat: ["Pendular Squat", "Pendulum Squat Machine"]
        case .beltSquat: ["Belt Squat Machine", "Hip Belt Squat", "Pit Shark"]
        case .smithMachine: [
            "Smith Press", "Smith Rack", "Multi Press", "Guided Barbell", "Guided Bar",
            "Counterbalanced Smith", "3D Smith", "Dual Axis Smith"
        ]
        default: []
        }
    }

    private var pressAliases: [String] {
        switch self {
        case .pecDeck: [
            "Pec Fly", "Butterfly", "Fly / Rear Delt", "Rear Delt Fly", "Reverse Fly", "Chest Fly",
            "Pec Deck Fly", "Fly Machine", "Rear Delt Machine", "Reverse Pec Deck", "Chest Fly Machine",
            "Rear Delt / Pec Fly", "Pectoral Fly"
        ]
        case .chestPressMachine: [
            "Seated Chest Press", "Converging Chest Press", "Chest Press Machine", "Machine Bench Press",
            "Iso-Lateral Chest Press", "Iso-Lateral Bench Press", "Iso-Lateral Incline Press",
            "Incline Chest Press", "Decline Chest Press", "Plate-Loaded Chest Press",
            "Seated Bench Press", "Vertical Press", "Wide Chest Press", "Bench Press Machine"
        ]
        case .shoulderPressMachine: [
            "Overhead Press Machine", "Converging Shoulder Press", "Iso-Lateral Shoulder Press",
            "Seated Shoulder Press", "Plate-Loaded Shoulder Press", "Military Press Machine", "Deltoid Press"
        ]
        case .lateralRaiseMachine: [
            "Side Lateral Raise Machine", "Machine Lateral Raise", "Deltoid Raise", "Delt Raise",
            "Side Raise Machine", "Lateral Deltoid Machine", "Iso-Lateral Lateral Raise",
            "Shoulder Lateral Raise", "Lateral Raise Station"
        ]
        case .pulloverMachine: [
            "Nautilus Pullover", "Lat Pullover Machine", "Seated Pullover", "Machine Pullover",
            "Pullover Station"
        ]
        default: []
        }
    }

    private var hipAliases: [String] {
        switch self {
        case .legCurl: [
            "Seated Leg Curl", "Lying Leg Curl", "Prone Leg Curl", "Hamstring Curl", "Kneeling Leg Curl",
            "Standing Leg Curl", "Leg Curl Machine", "Hamstring Curl Machine", "Iso-Lateral Leg Curl",
            "Leg Flexion", "Hamstring Machine"
        ]
        case .legExtension: [
            "Quad Extension", "Leg Extension Machine", "Knee Extension", "Iso-Lateral Leg Extension",
            "Quad Machine"
        ]
        case .hipAbductorAdductor: [
            "Hip Adductor", "Inner/Outer Thigh", "Thigh Machine", "Hip Abduction", "Hip Adduction",
            "Inner Thigh", "Outer Thigh", "Abduction / Adduction"
        ]
        case .multiHip: ["Multi-Hip", "4-Way Hip", "Hip Machine", "Total Hip", "Multi Hip Machine"]
        case .gluteKickback: [
            "Glute Drive", "Hip Thrust Machine", "Glute Press", "Kickback Machine", "Glute Kickback Machine",
            "Glute Machine", "Standing Glute", "Glute Builder", "Booty Builder"
        ]
        default: []
        }
    }

    private var trunkAliases: [String] {
        switch self {
        case .calfRaiseMachine: [
            "Rotary Calf", "Calf Machine", "Standing Calf Raise Machine", "Calf Raise Machine",
            "Iso-Lateral Calf", "Calf Extension", "Standing Calf Machine"
        ]
        case .seatedCalf: ["Seated Calf Machine", "Seated Calf Raise Machine", "Plate-Loaded Seated Calf"]
        case .abCrunchMachine: [
            "Abdominal Crunch", "Ab Machine", "Abdominal", "Abdominal Machine", "Seated Crunch",
            "Abdominal Isolator", "Ab Coaster", "Ab Crunch Station"
        ]
        case .torsoRotation: [
            "Rotary Torso", "Torso Twist", "Oblique Machine", "Torso Rotation Machine",
            "Rotary Torso Machine", "Seated Twist"
        ]
        case .backExtension: [
            "45° Hyperextension", "Hyperextension", "Roman Chair", "Lower Back", "Back Extension Machine",
            "Hyper Bench", "Hyperextension Bench", "Lower Back Machine", "Back Extension Bench",
            "45 Degree Back Extension", "Lumbar Extension", "Hyper"
        ]
        case .gluteHamDeveloper: [
            "GHD", "GHR", "Glute Ham Raise", "Glute-Ham Developer", "Glute Ham Bench",
            "Glute Ham Raise Machine", "Glute-Ham Raise"
        ]
        default: []
        }
    }

    private var armAliases: [String] {
        switch self {
        case .assistedDipPullUp: [
            "Assisted Chin/Dip", "Assisted Pull-Up", "Assisted Chin-Up", "Gravitron",
            "Assisted Pull-Up Machine", "Assisted Dip Machine", "Chin/Dip Assist", "Weight-Assisted Chin",
            "Counterweight Pull-Up", "Assisted Chin"
        ]
        case .preacherCurlMachine: [
            "Arm Curl", "Bicep Curl Machine", "Biceps Curl", "Biceps Curl Machine", "Machine Curl",
            "Iso-Lateral Biceps Curl", "Seated Curl", "Bicep Machine", "Machine Bicep Curl",
            "Preacher Machine"
        ]
        case .tricepsExtensionMachine: [
            "Arm Extension", "Triceps Press", "Tricep Machine", "Machine Triceps", "Seated Triceps Extension",
            "Iso-Lateral Triceps Extension", "Triceps Pushdown Machine", "Tricep Extension Machine",
            "Machine Triceps Extension"
        ]
        case .seatedDipMachine: [
            "Tricep Dip Machine", "Triceps Dip", "Dip Press", "Machine Dip", "Iso-Lateral Dip",
            "Seated Dip Press", "Triceps Dip Machine"
        ]
        case .rowMachine: [
            "Iso-Lateral Row", "Lever Row", "T-Bar Row", "T-Bar", "High Row", "Low Row (plate-loaded)",
            "Iso-Lateral High Row", "Iso-Lateral Low Row", "Iso-Lateral Front Row", "Plate-Loaded Row",
            "Diverging Seated Row", "Diverging Low Row", "Chest-Supported Row",
            "Chest Supported Row Machine", "Seated Row Machine", "Machine Row", "Hammer Strength Row",
            "Selectorized Row", "Selectorised Row", "Lever Row Machine", "Rear Delt Row"
        ]
        default: []
        }
    }

    private var cableAliases: [String] {
        switch self {
        case .latPulldown: [
            "Diverging Lat Pulldown", "Lat Pull Down", "Lat Machine", "Lat Pulldown Machine", "Pull Down",
            "Pulldown Machine", "Wide Grip Pulldown", "High Pulley Pulldown", "Lat Pulldown Station",
            "Pulldown Seat", "Lat Pulldown / Low Row"
        ]
        case .seatedRowMachine: [
            "Seated Row", "Low Row", "Long Pulley", "Low Pulley Row", "Seated Cable Row Machine",
            "Cable Seated Row", "Horizontal Row", "Low Pulley", "Rowing Station", "Seated Row Station",
            "Cable Row Seat"
        ]
        case .cableStation: [
            "Cable Crossover", "Dual Adjustable Pulley", "Functional Trainer", "Cable Machine",
            "Cable Column", "Cables", "Pulley", "Cable Pulley", "Crossover", "Cable Cross",
            "Adjustable Pulley", "Dual Cable Cross", "Cable Tower", "Multi-Gym", "Triceps Pushdown",
            "Cable Rack", "Cable Stack", "Functional Training Station", "DAP", "Kinesis", "Rope Pushdown"
        ]
        case .pullUpBar: [
            "Chin-Up Bar", "Pull Up Bar", "Chinning Bar", "Rig", "Chin Bar", "Pull-Up Station",
            "Chin-Up Station", "Power Tower", "Wall-Mounted Bar", "Doorway Bar", "Pull-Up Rig"
        ]
        case .dipStation: [
            "Dip Bars", "Parallel Bars", "Dip / Leg Raise Station", "Captain's Chair", "Dip Tower",
            "Leg Raise Station", "VKR", "Vertical Knee Raise", "Dip Stand", "Dip Bar"
        ]
        default: []
        }
    }

    private var cardioAliases: [String] {
        switch self {
        case .treadmill: ["Running Machine", "Treadmill Cardio", "Curved Treadmill", "Skillmill", "Woodway"]
        case .stationaryBike: [
            "Exercise Bike", "Upright Bike", "Recumbent Bike", "Spin Bike", "Air Bike", "Assault Bike",
            "Cycle", "Indoor Cycle", "Echo Bike", "Watt Bike", "Wattbike", "Fan Bike", "Peloton"
        ]
        case .elliptical: [
            "Cross Trainer", "Elliptical Trainer", "Crosstrainer", "X-Trainer", "Arc Trainer",
            "Elliptical Machine"
        ]
        case .rower: [
            "Rower", "Concept2", "Concept 2", "Erg", "Rowing Ergometer", "Row Erg", "Indoor Rower",
            "Rowing Ergo"
        ]
        case .stairClimber: [
            "Stairmaster", "Step Mill", "Stepper", "Stair Master", "Climbmill", "Stairclimber", "Stairs",
            "Stepmill", "Stair Machine", "Jacobs Ladder"
        ]
        case .skiErg: ["SkiErg", "Ski Machine", "Concept2 SkiErg", "Nordic Ski Machine", "Ski Trainer"]
        default: []
        }
    }

    /// The `seedID` of a bundled exercise whose free-exercise-db photograph (public domain,
    /// Unlicense) shows this station — the picker's thumbnail. Nil where nothing bundled shows
    /// it; those fall back to `symbolName`. The seed rows for the nil cases come from wger and
    /// ship with no photograph.
    public var representativeExerciseSeedID: String? {
        switch self {
        case .legPress: "Leg_Press"
        case .hackSquat: "Hack_Squat"
        case .pendulumSquat: nil // wger "Pendular hack" only, no photo
        case .beltSquat: nil // wger "Belt Squat" only, no photo
        case .smithMachine: "Smith_Machine_Squat"
        case .pecDeck: "Butterfly"
        case .chestPressMachine: "Machine_Bench_Press"
        case .shoulderPressMachine: "Machine_Shoulder_Military_Press"
        case .lateralRaiseMachine: nil // wger "Machine Lateral Raise" only, no photo
        case .pulloverMachine: nil // wger "Pullover Machine" only, no photo
        case .legCurl: "Lying_Leg_Curls"
        case .legExtension: "Leg_Extensions"
        case .hipAbductorAdductor: "Thigh_Abductor"
        case .multiHip: nil // no seeded exercise
        case .gluteKickback: nil // wger "Glute Kickback (Machine)" only, no photo
        case .calfRaiseMachine: "Standing_Calf_Raises"
        case .seatedCalf: "Seated_Calf_Raise"
        case .abCrunchMachine: "Ab_Crunch_Machine"
        case .torsoRotation: nil // wger "Rotary Torso Machine" only, no photo
        case .backExtension: "Hyperextensions_Back_Extensions"
        case .gluteHamDeveloper: "Glute_Ham_Raise"
        case .assistedDipPullUp: nil // the only assisted rows are band-assisted or wger, no photo
        case .preacherCurlMachine: "Machine_Preacher_Curls"
        case .tricepsExtensionMachine: "Machine_Triceps_Extension"
        case .seatedDipMachine: "Dip_Machine"
        case .rowMachine: "Leverage_Iso_Row"
        case .latPulldown: "Wide-Grip_Lat_Pulldown"
        case .seatedRowMachine: "Seated_Cable_Rows"
        case .cableStation: "Cable_Crossover"
        case .pullUpBar: "Pullups"
        case .dipStation: "Dips_-_Chest_Version" // Parallel_Bar_Dip shows a wooden CrossFit p-bar
        case .treadmill: "Running_Treadmill"
        case .stationaryBike: "Bicycling_Stationary"
        case .elliptical: "Elliptical_Trainer"
        case .rower: "Rowing_Stationary"
        case .stairClimber: "Stairmaster"
        case .skiErg: nil // wger "Ski Machine" only, no photo
        }
    }

    /// SF Symbol drawn when there is no photograph.
    public var symbolName: String {
        switch self {
        case .treadmill: "figure.run"
        case .stationaryBike: "figure.indoor.cycle"
        case .elliptical: "figure.elliptical"
        case .rower: "figure.rower"
        case .stairClimber: "figure.stair.stepper"
        case .skiErg: "figure.skiing.crosscountry"
        case .pullUpBar, .dipStation, .assistedDipPullUp: "figure.play"
        case .cableStation, .latPulldown, .seatedRowMachine: "cable.connector"
        default: "figure.strengthtraining.traditional"
        }
    }
}
