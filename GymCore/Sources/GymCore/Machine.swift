import Foundation

/// The closed list of gym stations an exercise can need, one level below the equipment *kind*
/// ("machine", "cable", "bodyweight"). A lifter ticks the stations their gym actually has on an
/// equipment profile, and everything that filters by equipment — library, picker, routine
/// warning, substitutions, the program generator — then only offers what is there.
///
/// Deliberately small and real: one case per station a commercial gym floor labels (the list
/// follows a typical Matrix / Technogym / Precor floor), not one per attachment or grip. A
/// station with no seeded exercise yet is still listed — it is the gym's inventory — and the
/// picker simply shows nothing under it. Choices worth knowing:
/// - `cableStation` is *one* station: crossover, functional trainer, single high/low pulley and
///   every triceps pushdown / straight-arm pulldown done on it. Lat pulldowns and seated cable
///   rows get their own cases because they are separate seats on most floors.
/// - `seatedRowMachine` is the cable seated-row seat (kind "cable"); `rowMachine` is every lever
///   row — plate-loaded Iso-Lateral, selectorised diverging / chest-supported, T-bar (kind
///   "machine"). Same movement, different stations.
/// - `pecDeck` covers both the fly and the rear-delt (reverse) setting of the one machine.
/// - `backExtension` is the 45° hyper / Roman chair; `gluteHamDeveloper` is the GHD, its own
///   station on the floors that have one (most PureGyms don't, so it is a separate tick).
/// - `tricepsExtensionMachine` is the seated triceps-extension machine; `seatedDipMachine` the
///   seated dip press; `dipStation` the bodyweight bars. Three different stations.
/// - Cardio stations are here too: a "Home" profile with a treadmill is a real profile.
public enum Machine: String, CaseIterable, Codable, Sendable {
    case legPress, hackSquat, pendulumSquat, beltSquat, smithMachine
    case pecDeck, chestPressMachine, shoulderPressMachine, lateralRaiseMachine, pulloverMachine
    case legCurl, legExtension, hipAbductorAdductor, multiHip, gluteKickback
    case calfRaiseMachine, seatedCalf, abCrunchMachine, torsoRotation, backExtension
    case gluteHamDeveloper, assistedDipPullUp, preacherCurlMachine, tricepsExtensionMachine
    case seatedDipMachine, rowMachine
    case latPulldown, seatedRowMachine, cableStation
    case pullUpBar, dipStation
    case treadmill, stationaryBike, elliptical, rower, stairClimber, skiErg

    /// The canonical name the profile editor and the "Needs: …" warning print.
    public var displayName: String {
        switch self {
        case .legPress: "Leg Press"
        case .hackSquat: "Hack Squat"
        case .pendulumSquat: "Pendulum Squat"
        case .beltSquat: "Belt Squat"
        case .smithMachine: "Smith Machine"
        case .pecDeck: "Pec Deck"
        case .chestPressMachine: "Chest Press"
        case .shoulderPressMachine: "Shoulder Press Machine"
        case .lateralRaiseMachine: "Lateral Raise Machine"
        case .pulloverMachine: "Pullover Machine"
        case .legCurl: "Leg Curl"
        case .legExtension: "Leg Extension"
        case .hipAbductorAdductor: "Hip Abductor / Adductor"
        case .multiHip: "Multi Hip"
        case .gluteKickback: "Glute Kickback"
        case .calfRaiseMachine: "Standing Calf Raise"
        case .seatedCalf: "Seated Calf Raise"
        case .abCrunchMachine: "Ab Crunch Machine"
        case .torsoRotation: "Torso Rotation"
        case .backExtension: "Back Extension"
        case .gluteHamDeveloper: "Glute Ham Developer"
        case .assistedDipPullUp: "Assisted Dip / Pull-Up"
        case .preacherCurlMachine: "Preacher Curl Machine"
        case .tricepsExtensionMachine: "Triceps Extension Machine"
        case .seatedDipMachine: "Seated Dip Machine"
        case .rowMachine: "Row Machine"
        case .latPulldown: "Lat Pulldown"
        case .seatedRowMachine: "Seated Cable Row"
        case .cableStation: "Cable Station"
        case .pullUpBar: "Pull-Up Bar"
        case .dipStation: "Dip Station"
        case .treadmill: "Treadmill"
        case .stationaryBike: "Stationary Bike"
        case .elliptical: "Elliptical"
        case .rower: "Rowing Machine"
        case .stairClimber: "Stair Climber"
        case .skiErg: "Ski Erg"
        }
    }

    /// The equipment kind (an `EquipmentOption` raw value on the app side) this station belongs
    /// to. A station is only on offer when its kind is ticked on the profile.
    public var equipmentType: String {
        switch self {
        case .latPulldown, .seatedRowMachine, .cableStation: "cable"
        case .pullUpBar, .dipStation: "bodyweight"
        default: "machine"
        }
    }

    /// True for the cardio stations, which the program generator never picks anyway.
    public var isCardio: Bool {
        switch self {
        case .treadmill, .stationaryBike, .elliptical, .rower, .stairClimber, .skiErg: true
        default: false
        }
    }

    /// Every kind that has at least one station, in the order the profile editor lists them.
    public static let equipmentTypes: [String] = ["machine", "cable", "bodyweight"]

    /// The stations of one kind, in declaration order.
    public static func machines(ofType type: String) -> [Machine] {
        allCases.filter { $0.equipmentType == type }
    }

    /// Whether `query` (a search-field string) names this station by its canonical name or any
    /// alias. Empty matches everything.
    ///
    /// A query of `minimumSubstringQueryLength` or more characters matches anywhere in a name;
    /// a shorter one has to start a word — "row" finds "Rower" and "Row Machine", but "rig" no
    /// longer offers the Upright Bike beside the Pull-Up Bar.
    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if trimmed.count >= Self.minimumSubstringQueryLength {
            return ([displayName] + aliases).contains { $0.range(of: trimmed, options: options) != nil }
        }
        return ([displayName] + aliases).contains { name in
            name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains {
                $0.range(of: trimmed, options: options.union(.anchored)) != nil
            }
        }
    }

    /// Queries at least this long match as substrings; shorter ones only at a word start.
    public static let minimumSubstringQueryLength = 4

    /// The stations matching `query`, in declaration order.
    public static func search(_ query: String) -> [Machine] {
        allCases.filter { $0.matches(query) }
    }
}
