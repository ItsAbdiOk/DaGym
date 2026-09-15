import Foundation

/// One filled slot: the template slot id and the library exercise chosen for it.
public struct ProgramPick: Hashable, Sendable {
    public var slotID: String
    public var exerciseID: UUID

    public init(slotID: String, exerciseID: UUID) {
        self.slotID = slotID
        self.exerciseID = exerciseID
    }
}

/// A template with every slot filled and a name — what the preview shows and `apply` creates.
public struct ProgramDraft: Hashable, Sendable {
    public var name: String
    public var picks: [ProgramPick]

    public init(name: String, picks: [ProgramPick]) {
        self.name = name
        self.picks = picks
    }

    public static let maxNameLength = 40

    public func exerciseID(for slotID: String) -> UUID? {
        picks.first { $0.slotID == slotID }?.exerciseID
    }
}

/// Why a draft was refused. Each case names the offending slot, exercise or muscle so a test
/// (and a debug log) can say exactly which rule fired.
public enum ProgramDraftError: Error, Hashable, Sendable {
    case emptyName
    case unknownSlot(String)
    case missingSlot(String)
    /// An exercise id that isn't in the candidate pool the model was given.
    case foreignExercise(UUID)
    /// The pick's primary muscles don't include the slot's muscle.
    case wrongMuscle(slotID: String)
    case excludedEquipment(UUID)
    case excludedMuscle(UUID)
    case volumeOutOfBounds(Muscle, sets: Int)
}

/// The candidate pool the picker (model or rule) chooses from: the library filtered to what the
/// request allows and what the template needs, capped per (muscle, mechanic) so the prompt stays
/// a few dozen lines. Deterministic order (name), so tests and prompts are stable.
public enum ProgramExercisePool {
    public static let maxPerMuscleAndMechanic = 6

    public static func candidates(
        for template: ProgramTemplate, library: [SubstitutionCandidate], request: ProgramRequest
    ) -> [SubstitutionCandidate] {
        let tracked = template.trackedMuscles
        let allowed = library.filter { candidate in
            request.usableEquipment.contains(candidate.equipment)
                && candidate.loggingStyle != "cardio"
                && !Set(candidate.primary).isDisjoint(with: tracked)
                && Set(candidate.primary).isDisjoint(with: request.excludedMuscles)
        }
        .sorted { $0.name < $1.name }
        var counts: [String: Int] = [:]
        var pool: [SubstitutionCandidate] = []
        for candidate in allowed {
            // Counted against the first tracked primary muscle, so a squat isn't admitted twice.
            guard let muscle = candidate.primary.first(where: tracked.contains) else { continue }
            let key = "\(muscle.rawValue)|\(candidate.mechanic)"
            guard counts[key, default: 0] < maxPerMuscleAndMechanic else { continue }
            counts[key, default: 0] += 1
            pool.append(candidate)
        }
        return pool
    }
}

/// The strict gate every draft passes before the preview: ids in the pool, every slot filled
/// with an exercise that actually trains that slot's muscle, no excluded equipment or muscle,
/// and weekly sets per muscle inside the template's bounds. Throws the first rule broken.
public enum ProgramDraftValidator {
    public static func validate(
        _ draft: ProgramDraft, template: ProgramTemplate, pool: [SubstitutionCandidate],
        request: ProgramRequest
    ) throws -> ProgramDraft {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProgramDraftError.emptyName }
        let poolByID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let slotsByID = Dictionary(
            template.slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        var picksBySlot: [String: UUID] = [:]
        for pick in draft.picks {
            guard let slot = slotsByID[pick.slotID] else { throw ProgramDraftError.unknownSlot(pick.slotID) }
            guard let exercise = poolByID[pick.exerciseID] else {
                throw ProgramDraftError.foreignExercise(pick.exerciseID)
            }
            try check(exercise, fills: slot, request: request)
            // A second pick for the same slot is ignored, not an error — the first one wins.
            if picksBySlot[slot.id] == nil { picksBySlot[slot.id] = exercise.id }
        }
        let ordered = try template.slots.map { slot -> ProgramPick in
            guard let exerciseID = picksBySlot[slot.id] else { throw ProgramDraftError.missingSlot(slot.id) }
            return ProgramPick(slotID: slot.id, exerciseID: exerciseID)
        }
        try checkVolume(picksBySlot: picksBySlot, template: template, poolByID: poolByID)
        return ProgramDraft(name: String(name.prefix(ProgramDraft.maxNameLength)), picks: ordered)
    }

    private static func check(
        _ exercise: SubstitutionCandidate, fills slot: ProgramSlot, request: ProgramRequest
    ) throws {
        guard exercise.primary.contains(slot.muscle) else {
            throw ProgramDraftError.wrongMuscle(slotID: slot.id)
        }
        guard request.usableEquipment.contains(exercise.equipment) else {
            throw ProgramDraftError.excludedEquipment(exercise.id)
        }
        guard Set(exercise.primary).isDisjoint(with: request.excludedMuscles) else {
            throw ProgramDraftError.excludedMuscle(exercise.id)
        }
    }

    /// Every tracked muscle inside the bounds, and no muscle at all — tracked or not — over
    /// the top: a pick's extra primary movers count too.
    private static func checkVolume(
        picksBySlot: [String: UUID], template: ProgramTemplate, poolByID: [UUID: SubstitutionCandidate]
    ) throws {
        var weeklySets: [Muscle: Int] = [:]
        for slot in template.slots {
            guard let exerciseID = picksBySlot[slot.id], let exercise = poolByID[exerciseID] else { continue }
            for muscle in exercise.primary { weeklySets[muscle, default: 0] += slot.sets }
        }
        let bounds = template.weeklySetBounds
        for muscle in Muscle.allCases {
            let sets = weeklySets[muscle, default: 0]
            let tracked = template.trackedMuscles.contains(muscle)
            guard (tracked && !bounds.contains(sets)) || sets > bounds.upperBound else { continue }
            throw ProgramDraftError.volumeOutOfBounds(muscle, sets: sets)
        }
    }
}

/// The rule picker — the template's default exercises when no model is available, and the
/// fallback when the model's draft fails validation. Per slot: the best pool match by muscle
/// and mechanic, preferring a free-weight compound, never reusing an exercise within a day and
/// preferring one not yet used in the whole program. Nil when a slot can't be filled at all
/// (the pool has nothing for that muscle) — the caller says so rather than inventing a lift.
public enum ProgramDefaultPicks {
    public static func draft(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) -> ProgramDraft? {
        var picks: [ProgramPick] = []
        var usedInProgram = Set<UUID>()
        for day in template.days {
            var usedToday = Set<UUID>()
            for slot in day.slots {
                let eligible = pool.filter { $0.primary.contains(slot.muscle) && !usedToday.contains($0.id) }
                guard let best = eligible.min(by: {
                    rank($0, slot: slot, used: usedInProgram) < rank($1, slot: slot, used: usedInProgram)
                }) else { return nil }
                usedToday.insert(best.id)
                usedInProgram.insert(best.id)
                picks.append(ProgramPick(slotID: slot.id, exerciseID: best.id))
            }
        }
        let draft = ProgramDraft(name: template.splitName, picks: picks)
        return (try? ProgramDraftValidator.validate(draft, template: template, pool: pool, request: request))
    }

    /// Lower is better: mechanic match, then unused-so-far, then free weights for compounds and
    /// cables/machines for isolation, then name for determinism.
    private static func rank(
        _ candidate: SubstitutionCandidate, slot: ProgramSlot, used: Set<UUID>
    ) -> (Int, String) {
        let mechanic = candidate.mechanic == slot.mechanic ? 0 : 100
        let reused = used.contains(candidate.id) ? 10 : 0
        let equipmentOrder: [String] = slot.mechanic == "compound"
            ? ["barbell", "dumbbell", "machine", "cable", "bodyweight"]
            : ["cable", "machine", "dumbbell", "barbell", "bodyweight"]
        let equipment = equipmentOrder.firstIndex(of: candidate.equipment) ?? equipmentOrder.count
        return (mechanic + reused + equipment, candidate.name)
    }
}
