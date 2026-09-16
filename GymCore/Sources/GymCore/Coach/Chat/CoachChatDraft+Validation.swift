import Foundation

/// The gate between the model and the store. Every exercise must be in the lifter's library
/// (by id, or by exact name when the model only has a name), doable with the profile's
/// equipment and stations, and every set scheme inside `Limits`. On success the draft comes
/// back canonical — ids filled in, names in the library's spelling, name and notes trimmed —
/// so the store applies it without a second lookup. On failure every reason is listed.
extension CoachChatDraft {
    public func validate(
        availability: EquipmentAvailability, library: [SubstitutionCandidate]
    ) -> Result<CoachChatDraft, CoachChatDraftRejection> {
        let resolver = CoachChatExerciseResolver(library: library, availability: availability)
        var reasons: [String] = []
        let validated: CoachChatDraft
        switch self {
        case .routine(let proposal):
            validated = .routine(Self.validate(proposal, resolver: resolver, reasons: &reasons))
        case .program(let proposal):
            validated = .program(Self.validate(proposal, resolver: resolver, reasons: &reasons))
        case .schedule(let proposal):
            validated = .schedule(Self.validate(proposal, reasons: &reasons))
        case .deload(let proposal):
            validated = .deload(Self.validate(proposal, resolver: resolver, reasons: &reasons))
        case .swap(let proposal):
            validated = .swap(Self.validate(proposal, resolver: resolver, reasons: &reasons))
        }
        return reasons.isEmpty ? .success(validated) : .failure(CoachChatDraftRejection(reasons: reasons))
    }

    // MARK: - Routine

    static func validate(
        _ proposal: RoutineProposal, resolver: CoachChatExerciseResolver, reasons: inout [String]
    ) -> RoutineProposal {
        var result = proposal
        result.name = trimmed(proposal.name, max: Limits.maxNameLength)
        result.notes = proposal.notes.map { trimmed($0, max: Limits.maxNotesLength) }
            .flatMap { $0.isEmpty ? nil : $0 }
        if result.name.isEmpty { reasons.append("The routine needs a name.") }
        guard Limits.exercisesPerRoutine.contains(proposal.exercises.count) else {
            reasons.append(
                "A routine has \(Limits.exercisesPerRoutine.lowerBound)–"
                    + "\(Limits.exercisesPerRoutine.upperBound) exercises, not \(proposal.exercises.count)."
            )
            return result
        }
        var seen = Set<UUID>()
        result.exercises = proposal.exercises.map { spec in
            var spec = spec
            guard let exercise = resolver.resolve(
                id: spec.exerciseID, name: spec.exerciseName, reasons: &reasons
            ) else { return spec }
            spec.exerciseID = exercise.id
            spec.exerciseName = exercise.name
            spec.reason = trimmedReason(spec.reason)
            if !seen.insert(exercise.id).inserted {
                reasons.append("'\(exercise.name)' appears twice; list each exercise once.")
            }
            check(spec, reasons: &reasons)
            return spec
        }
        return result
    }

    /// Set count, reps, weight, RPE and rest inside `Limits` for one exercise.
    static func check(_ spec: CoachChatExerciseSpec, reasons: inout [String]) {
        let label = spec.label
        if !Limits.setsPerExercise.contains(spec.sets.count) {
            reasons.append(
                "'\(label)' has \(spec.sets.count) sets; use \(Limits.setsPerExercise.lowerBound)–"
                    + "\(Limits.setsPerExercise.upperBound)."
            )
        }
        for set in spec.sets {
            if !Limits.repsRange.contains(set.targetReps) {
                reasons.append(
                    "'\(label)' asks for \(set.targetReps) reps; use \(Limits.repsRange.lowerBound)–"
                        + "\(Limits.repsRange.upperBound)."
                )
            }
            if let weight = set.targetWeightKg, weight < 0 || weight > Limits.maxWeightKg {
                reasons.append("'\(label)' asks for \(weight) kg; use 0–\(Int(Limits.maxWeightKg)) kg.")
            }
            if let rpe = set.rpe, !Limits.rpeRange.contains(rpe) {
                reasons.append("'\(label)' asks for RPE \(rpe); use 1–10.")
            }
        }
        if let rest = spec.restSeconds, !Limits.restSecondsRange.contains(rest) {
            reasons.append("'\(label)' rests \(rest) s; use 0–\(Limits.restSecondsRange.upperBound) s.")
        }
    }

    // MARK: - Program

    static func validate(
        _ proposal: ProgramProposal, resolver: CoachChatExerciseResolver, reasons: inout [String]
    ) -> ProgramProposal {
        var result = proposal
        result.name = trimmed(proposal.name, max: Limits.maxNameLength)
        if result.name.isEmpty { reasons.append("The program needs a name.") }
        let days = ProgramRequest.daysRange
        if !days.contains(proposal.daysPerWeek) {
            reasons.append(
                "days_per_week must be \(days.lowerBound)–\(days.upperBound), not \(proposal.daysPerWeek)."
            )
        }
        if let minutes = proposal.sessionMinutes, !ProgramRequest.sessionMinutesRange.contains(minutes) {
            let range = ProgramRequest.sessionMinutesRange
            reasons.append(
                "session_minutes must be \(range.lowerBound)–\(range.upperBound), not \(minutes)."
            )
        }
        if proposal.routines.count > max(proposal.daysPerWeek, days.lowerBound) {
            reasons.append(
                "A \(proposal.daysPerWeek)-day program cannot have \(proposal.routines.count) routines."
            )
        }
        result.routines = proposal.routines.map { routine in
            var routineReasons: [String] = []
            let validated = validate(routine, resolver: resolver, reasons: &routineReasons)
            reasons.append(contentsOf: routineReasons.map { "\(routine.name): \($0)" })
            return validated
        }
        let names = result.routines.map { $0.name.lowercased() }
        if Set(names).count != names.count { reasons.append("Two routines share a name; give each its own.") }
        return result
    }

    // MARK: - Schedule

    /// Routine ids are checked by the store (it owns the routine list); here only the shape.
    static func validate(_ proposal: ScheduleProposal, reasons: inout [String]) -> ScheduleProposal {
        if proposal.days.isEmpty { reasons.append("The schedule names no training days.") }
        return proposal
    }

    // MARK: - Deload

    static func validate(
        _ proposal: DeloadProposal, resolver: CoachChatExerciseResolver, reasons: inout [String]
    ) -> DeloadProposal {
        var result = proposal
        if let exercise = resolver.resolve(
            id: proposal.exerciseID, name: proposal.exerciseName, checkEquipment: false, reasons: &reasons
        ) {
            result.exerciseID = exercise.id
            result.exerciseName = exercise.name
        }
        if !Limits.deloadPercentRange.contains(proposal.percent) {
            reasons.append(
                "percent must be \(Int(Limits.deloadPercentRange.lowerBound))–"
                    + "\(Int(Limits.deloadPercentRange.upperBound)), not \(proposal.percent)."
            )
        }
        return result
    }

    // MARK: - Swap

    static func validate(
        _ proposal: SwapProposal, resolver: CoachChatExerciseResolver, reasons: inout [String]
    ) -> SwapProposal {
        var result = proposal
        // The outgoing exercise only has to exist — it may well be the one the gym lacks.
        let from = resolver.resolve(
            id: proposal.fromExerciseID, name: proposal.fromExerciseName, checkEquipment: false,
            reasons: &reasons
        )
        let to = resolver.resolve(id: proposal.toExerciseID, name: proposal.toExerciseName, reasons: &reasons)
        if let from {
            result.fromExerciseID = from.id
            result.fromExerciseName = from.name
        }
        if let to {
            result.toExerciseID = to.id
            result.toExerciseName = to.name
        }
        if let from, let to, from.id == to.id {
            reasons.append("'\(from.name)' cannot be swapped for itself.")
        }
        return result
    }

    /// A reason capped to the card's line; a blank one drops to nil so the card shows no row.
    static func trimmedReason(_ reason: String?) -> String? {
        guard let reason else { return nil }
        let text = trimmed(reason, max: Limits.maxReasonLength)
        return text.isEmpty ? nil : text
    }

    static func trimmed(_ text: String, max: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }
}

/// Finds a library exercise by id or by exact (case-insensitive) name and checks it against
/// the equipment profile, appending a reason for whatever fails.
struct CoachChatExerciseResolver {
    let library: [SubstitutionCandidate]
    let availability: EquipmentAvailability
    private let byID: [UUID: SubstitutionCandidate]
    private let byName: [String: SubstitutionCandidate]

    init(library: [SubstitutionCandidate], availability: EquipmentAvailability) {
        self.library = library
        self.availability = availability
        byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byName = Dictionary(
            library.map { (Self.key($0.name), $0) }, uniquingKeysWith: { first, _ in first }
        )
    }

    func resolve(
        id: UUID?, name: String?, checkEquipment: Bool = true, reasons: inout [String]
    ) -> SubstitutionCandidate? {
        let found: SubstitutionCandidate?
        if let id {
            found = byID[id]
            if found == nil { reasons.append("No exercise with id \(id.uuidString); use search_exercises.") }
        } else if let name, !Self.key(name).isEmpty {
            found = byName[Self.key(name)] ?? closest(to: name)
            if found == nil {
                let hint = suggestions(for: name)
                reasons.append(
                    "Unknown exercise '\(name)'"
                        + (hint.isEmpty ? "" : " — closest in the library: \(hint.joined(separator: ", "))")
                        + "; use search_exercises for the exact name."
                )
            }
        } else {
            found = nil
            reasons.append("An exercise needs an exercise_id or exercise_name.")
        }
        guard let exercise = found, checkEquipment else { return found }
        switch availability.verdict(equipment: exercise.equipment, machine: exercise.machine) {
        case .allowed:
            return exercise
        case .missingType(let type):
            reasons.append("'\(exercise.name)' needs \(type), which the lifter's gym does not have.")
        case .missingMachine(let machine):
            reasons.append(
                "'\(exercise.name)' needs a \(machine.displayName), which the lifter's gym does not have."
            )
        }
        return exercise
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A model writes "Lat Pulldown" for the library's "Wide-Grip Lat Pulldown" and "DB Bench"
    /// for "Dumbbell Bench Press"; rejecting those cost a whole round trip each. The name is
    /// matched on words: every word of the request must appear in the library name (common
    /// abbreviations expanded), and among the matches the fewest extra words wins, allowed
    /// exercises before blocked ones, shorter names before longer.
    func closest(to name: String) -> SubstitutionCandidate? {
        let wanted = Self.words(name)
        guard !wanted.isEmpty else { return nil }
        let scored = library.compactMap { candidate -> (SubstitutionCandidate, Int, Int)? in
            let have = Self.words(candidate.name)
            guard wanted.allSatisfy({ word in have.contains(word) }) else { return nil }
            let allowed = availability.verdict(equipment: candidate.equipment, machine: candidate.machine)
                == .allowed ? 0 : 1
            return (candidate, have.count - wanted.count, allowed)
        }
        return scored.min { lhs, rhs in
            (lhs.1, lhs.2, lhs.0.name.count) < (rhs.1, rhs.2, rhs.0.name.count)
        }?.0
    }

    /// Up to three library names sharing most words with `name`, for the rejection message.
    func suggestions(for name: String) -> [String] {
        let wanted = Self.words(name)
        guard !wanted.isEmpty else { return [] }
        return library
            .map { ($0.name, Set(Self.words($0.name)).intersection(wanted).count) }
            .filter { $0.1 > 0 }
            .sorted { ($0.1, -$0.0.count) > ($1.1, -$1.0.count) }
            .prefix(3)
            .map(\.0)
    }

    private static let abbreviations: [String: String] = [
        "db": "dumbbell", "bb": "barbell", "dbs": "dumbbell", "kb": "kettlebell", "ohp": "overhead",
        "rdl": "romanian", "sldl": "stiff", "wg": "wide", "cg": "close", "ez": "ez", "lat": "lat"
    ]

    /// Lower-cased words with any parenthesised qualifier ("(Barbell)", "(Machine)") dropped —
    /// export-style qualifiers name equipment the library folds into the name itself.
    private static func words(_ name: String) -> [String] {
        var text = name.lowercased()
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }
        return text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { abbreviations[String($0)] ?? String($0) }
            .filter { !["the", "a", "with", "on", "and"].contains($0) }
    }
}
