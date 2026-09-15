import Foundation

/// What the lifter is training for. Decides sets, rep range and the progression rule.
public enum TrainingGoal: String, CaseIterable, Codable, Hashable, Sendable {
    case strength, hypertrophy, general

    public var displayName: String {
        switch self {
        case .strength: "Strength"
        case .hypertrophy: "Muscle"
        case .general: "General fitness"
        }
    }
}

public enum ExperienceLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case beginner, intermediate, advanced

    public var displayName: String { rawValue.capitalized }
}

/// The program questionnaire's answers — the whole input to `ProgramTemplateEngine`.
public struct ProgramRequest: Hashable, Sendable {
    public var goal: TrainingGoal
    public var daysPerWeek: Int
    public var sessionMinutes: Int
    public var experience: ExperienceLevel
    /// Equipment kinds the lifter has ("barbell", "dumbbell", "machine", "cable", "bodyweight"…)
    /// and, when their profile narrows a kind to stations, which stations.
    public var equipmentAvailability: EquipmentAvailability
    /// The ticked kinds alone — `equipmentAvailability.types`.
    public var availableEquipment: Set<String> {
        get { equipmentAvailability.types }
        set { equipmentAvailability.types = newValue }
    }
    /// Equipment the lifter wants left out even though they have it.
    public var excludedEquipment: Set<String>
    /// Muscles to leave untrained (an injury, a preference) — no slot is created for them and no
    /// pick may load them as a primary mover.
    public var excludedMuscles: Set<Muscle>

    public static let daysRange = 2...6
    public static let sessionMinutesRange = 30...90

    public init(
        goal: TrainingGoal, daysPerWeek: Int, sessionMinutes: Int, experience: ExperienceLevel,
        availableEquipment: Set<String>, excludedEquipment: Set<String> = [],
        excludedMuscles: Set<Muscle> = [], equipmentAvailability: EquipmentAvailability? = nil
    ) {
        self.goal = goal
        self.daysPerWeek = min(max(daysPerWeek, Self.daysRange.lowerBound), Self.daysRange.upperBound)
        self.sessionMinutes = min(
            max(sessionMinutes, Self.sessionMinutesRange.lowerBound), Self.sessionMinutesRange.upperBound
        )
        self.experience = experience
        self.equipmentAvailability = equipmentAvailability ?? EquipmentAvailability(types: availableEquipment)
        self.excludedEquipment = excludedEquipment
        self.excludedMuscles = excludedMuscles
    }

    /// Equipment a pick may use: what the lifter has, minus what they've excluded.
    public var usableEquipment: Set<String> { availableEquipment.subtracting(excludedEquipment) }

    /// Whether a pick may use `candidate`: its kind is usable and, if it needs a station, the
    /// profile has that station.
    public func allows(_ candidate: SubstitutionCandidate) -> Bool {
        equipmentAvailability.subtracting(types: excludedEquipment).allows(candidate)
    }
}

/// One exercise slot in a template day: which muscle it must train, whether a compound or an
/// isolation move is wanted, and the sets × reps the planned sets get.
public struct ProgramSlot: Hashable, Sendable, Identifiable {
    public var id: String
    public var muscle: Muscle
    /// "compound" or "isolation" — a preference for the picker, not a validator requirement.
    public var mechanic: String
    public var sets: Int
    public var repLow: Int
    public var repHigh: Int

    public init(id: String, muscle: Muscle, mechanic: String, sets: Int, repLow: Int, repHigh: Int) {
        self.id = id
        self.muscle = muscle
        self.mechanic = mechanic
        self.sets = sets
        self.repLow = repLow
        self.repHigh = repHigh
    }
}

public struct ProgramDay: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var slots: [ProgramSlot]

    public init(id: String, name: String, slots: [ProgramSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }
}

/// The deterministic skeleton of a program: the split, each day's slots, the cycle length and
/// the progression rule. The model never changes any of this — it only fills the slots.
public struct ProgramTemplate: Hashable, Sendable {
    public var splitName: String
    public var days: [ProgramDay]
    public var weeks: Int
    public var rule: ProgressionRule
    /// Sets per muscle per week every filled program must land in, counting a pick's sets toward
    /// each of its primary muscles.
    public var weeklySetBounds: ClosedRange<Int>

    public init(
        splitName: String, days: [ProgramDay], weeks: Int, rule: ProgressionRule,
        weeklySetBounds: ClosedRange<Int>
    ) {
        self.splitName = splitName
        self.days = days
        self.weeks = weeks
        self.rule = rule
        self.weeklySetBounds = weeklySetBounds
    }

    public var slots: [ProgramSlot] { days.flatMap(\.slots) }

    /// Every muscle some slot targets — the set the validator requires coverage for.
    public var trackedMuscles: Set<Muscle> { Set(slots.map(\.muscle)) }

    /// Weekly sets the template itself prescribes per muscle, before any pick's secondary
    /// primaries are counted.
    public func templateWeeklySets(for muscle: Muscle) -> Int {
        slots.filter { $0.muscle == muscle }.reduce(0) { $0 + $1.sets }
    }
}

/// Builds `ProgramTemplate`s from a questionnaire. Pure and tested per goal: same request, same
/// template. Splits, slot blueprints and set/rep schemes are fixed tables below — the
/// conventional choices, not anything clever.
public enum ProgramTemplateEngine {
    enum DayKind: String {
        case fullBody = "Full Body", upper = "Upper", lower = "Lower"
        case push = "Push", pull = "Pull", legs = "Legs"
    }

    public static let weeklySetBounds = 3...30
    public static let weeks = 4

    public static func template(for request: ProgramRequest) -> ProgramTemplate {
        let (splitName, kinds) = split(for: request)
        let slotCount = slotCount(for: request)
        var occurrences: [DayKind: Int] = [:]
        let days = kinds.enumerated().map { index, kind -> ProgramDay in
            let occurrence = occurrences[kind, default: 0]
            occurrences[kind] = occurrence + 1
            let letter = kinds.filter { $0 == kind }.count > 1 ? " \(["A", "B", "C"][occurrence % 3])" : ""
            let blueprint = blueprint(for: kind, variant: occurrence)
                .filter { !request.excludedMuscles.contains($0.muscle) }
                .prefix(slotCount)
            let slots = blueprint.enumerated().map { slotIndex, entry in
                ProgramSlot(
                    id: "d\(index + 1)s\(slotIndex + 1)", muscle: entry.muscle, mechanic: entry.mechanic,
                    sets: sets(for: request, mechanic: entry.mechanic),
                    repLow: repRange(for: request.goal, mechanic: entry.mechanic).lowerBound,
                    repHigh: repRange(for: request.goal, mechanic: entry.mechanic).upperBound
                )
            }
            return ProgramDay(id: "d\(index + 1)", name: kind.rawValue + letter, slots: slots)
        }
        return ProgramTemplate(
            splitName: splitName, days: days, weeks: weeks, rule: rule(for: request.goal),
            weeklySetBounds: weeklySetBounds
        )
    }

    /// One deload week closing the cycle, the rest normal — `StarterPrograms.weekKinds`' shape.
    public static func weekIsDeload(_ index: Int, weeks: Int) -> Bool { index == weeks }

    static func split(for request: ProgramRequest) -> (String, [DayKind]) {
        switch request.daysPerWeek {
        case ...2: ("Full Body", [.fullBody, .fullBody])
        case 3:
            request.goal == .hypertrophy && request.experience != .beginner
                ? ("Push/Pull/Legs", [.push, .pull, .legs])
                : ("Full Body", [.fullBody, .fullBody, .fullBody])
        case 4: ("Upper/Lower", [.upper, .lower, .upper, .lower])
        case 5: ("Upper/Lower + Push/Pull/Legs", [.upper, .lower, .push, .pull, .legs])
        default: ("Push/Pull/Legs ×2", [.push, .pull, .legs, .push, .pull, .legs])
        }
    }

    /// Roughly ten minutes an exercise, with a beginner capped at five.
    static func slotCount(for request: ProgramRequest) -> Int {
        let byLength: Int
        switch request.sessionMinutes {
        case ..<45: byLength = 4
        case ..<60: byLength = 5
        case ..<75: byLength = 6
        default: byLength = 7
        }
        return request.experience == .beginner ? min(byLength, 5) : byLength
    }

    static func sets(for request: ProgramRequest, mechanic: String) -> Int {
        let base: Int
        switch request.goal {
        case .strength: base = mechanic == "compound" ? 4 : 3
        case .hypertrophy, .general: base = 3
        }
        return request.experience == .advanced && mechanic == "compound" ? base + 1 : base
    }

    static func repRange(for goal: TrainingGoal, mechanic: String) -> ClosedRange<Int> {
        switch goal {
        case .strength: mechanic == "compound" ? 3...5 : 6...8
        case .hypertrophy: mechanic == "compound" ? 6...10 : 10...15
        case .general: 6...10
        }
    }

    static func rule(for goal: TrainingGoal) -> ProgressionRule {
        switch goal {
        case .strength: .linear(incrementKg: 2.5)
        case .hypertrophy: .doubleProgression(low: 8, high: 12, incrementKg: 2.5)
        case .general: .doubleProgression(low: 6, high: 10, incrementKg: 2.5)
        }
    }

    /// Ordered (compounds first) slot blueprints. `variant` 1 rotates the compounds so an A/B pair
    /// doesn't open with the same lift twice.
    static func blueprint(for kind: DayKind, variant: Int) -> [(muscle: Muscle, mechanic: String)] {
        let compound = "compound", isolation = "isolation"
        let table: [(Muscle, String)]
        switch kind {
        case .fullBody:
            table = [
                (.quads, compound), (.chest, compound), (.lats, compound), (.hams, compound),
                (.delts, compound), (.biceps, isolation), (.triceps, isolation), (.abs, isolation)
            ]
        case .upper:
            table = [
                (.chest, compound), (.lats, compound), (.delts, compound), (.traps, compound),
                (.triceps, isolation), (.biceps, isolation), (.chest, isolation)
            ]
        case .lower, .legs:
            table = [
                (.quads, compound), (.hams, compound), (.glutes, compound), (.lowerBack, compound),
                (.calves, isolation), (.abs, isolation), (.quads, isolation)
            ]
        case .push:
            table = [
                (.chest, compound), (.delts, compound), (.chest, compound), (.triceps, isolation),
                (.delts, isolation), (.triceps, isolation), (.chest, isolation)
            ]
        case .pull:
            table = [
                (.lats, compound), (.traps, compound), (.lats, compound), (.biceps, isolation),
                (.traps, isolation), (.biceps, isolation), (.forearms, isolation)
            ]
        }
        let compounds = table.filter { $0.1 == compound }
        let isolations = table.filter { $0.1 == isolation }
        let rotated = variant % 2 == 1 && compounds.count > 1
            ? Array(compounds[1...]) + [compounds[0]] : compounds
        return (rotated + isolations).map { (muscle: $0.0, mechanic: $0.1) }
    }
}
