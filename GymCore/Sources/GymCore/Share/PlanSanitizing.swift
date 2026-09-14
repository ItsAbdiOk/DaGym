import Foundation

/// The bounds a hand-edited or buggy `.gymplan` file is held to. A shared plan is untrusted input
/// from another person's device: nothing in it may be written straight into `RoutineModel`,
/// `ProgramModel`, `ExerciseModel` or `PlannedSetModel` without being clamped first.
public enum PlanLimits {
    public static let maxRepRange = 50
    public static let maxProgramWeeks = 52
    /// A day cycle longer than this is a corrupt file, not a real program.
    public static let maxProgramDays = 366
    public static let maxRestSeconds = 3600
    public static let maxIncrementKg = 100.0
    public static let maxNameLength = 120
    public static let maxNotesLength = 2000
    public static let maxInstructionsLength = 8000
}

/// Clamps and drops the numbers a hand-edited or buggy `.gymplan` file could otherwise insert
/// straight into the store — negative rest, non-positive target reps, a NaN or negative target
/// weight, an inverted rep range, an unknown set kind, an absurd program length, a nameless
/// exercise that would pollute the name index, megabytes of "instructions" — plus clearing a
/// superset group a drop has left with a single member. Pure and SwiftData-free so it's testable
/// without a `ModelContainer`; the app layer (`RootView.loadPlanImport`) calls it on every
/// document right after `PlanCodec.decode`, before anything sees it.
public extension PlanDocument {
    func sanitised() -> PlanDocument {
        var result = self
        result.exercises = exercises.compactMap { $0.sanitised() }
        result.routines = routines.map { $0.sanitised() }
        result.program = program?.sanitised(routineIDs: Set(result.routines.map(\.id)))
        return result
    }
}

extension PlanExercise {
    /// `nil` for a nameless exercise: an empty name would create an unnamed custom exercise and
    /// take over the importer's `name.lowercased()` index for the empty string, so every later
    /// unnamed slot would resolve to it. Everything else is clamped rather than dropped.
    func sanitised() -> PlanExercise? {
        let name = PlanText.clamp(self.name, to: PlanLimits.maxNameLength)
        guard !name.isEmpty else { return nil }
        var result = self
        result.name = name
        result.incrementKg = PlanNumber.increment(incrementKg)
        result.restSeconds = PlanNumber.rest(restSeconds)
        result.instructions = PlanText.clamp(instructions, to: PlanLimits.maxInstructionsLength)
        result.notes = PlanText.clamp(notes, to: PlanLimits.maxNotesLength)
        return result
    }
}

extension PlanRoutine {
    /// Clamps `repRangeLow`/`repRangeHigh` to 1...50 and swaps them into order, drops nameless
    /// exercise slots, sanitises the rest, then clears any `supersetGroup` left with only one
    /// surviving member.
    func sanitised() -> PlanRoutine {
        var result = self
        result.name = PlanText.clamp(name, to: PlanLimits.maxNameLength)
        result.notes = PlanText.clamp(notes, to: PlanLimits.maxNotesLength)
        var low = clampedRepRange(repRangeLow)
        var high = clampedRepRange(repRangeHigh)
        if low > high { swap(&low, &high) }
        result.repRangeLow = low
        result.repRangeHigh = high
        result.exercises = Self.clearOrphanSupersets(exercises.compactMap { $0.sanitised() })
        return result
    }

    private func clampedRepRange(_ value: Int) -> Int {
        min(max(value, 1), PlanLimits.maxRepRange)
    }

    private static func clearOrphanSupersets(_ slots: [PlanRoutineExercise]) -> [PlanRoutineExercise] {
        var counts: [Int: Int] = [:]
        for slot in slots {
            if let group = slot.supersetGroup { counts[group, default: 0] += 1 }
        }
        return slots.map { slot in
            var slot = slot
            if let group = slot.supersetGroup, counts[group] == 1 {
                slot.supersetGroup = nil
            }
            return slot
        }
    }
}

extension PlanRoutineExercise {
    /// Drops the whole slot when it names no exercise (nothing could resolve it, and an empty
    /// name would otherwise create a nameless custom); otherwise drops a non-positive
    /// `restOverrideSeconds`, bounds the note, and sanitises every set.
    func sanitised() -> PlanRoutineExercise? {
        let name = PlanText.clamp(exerciseName, to: PlanLimits.maxNameLength)
        guard !name.isEmpty else { return nil }
        var result = self
        result.exerciseName = name
        result.note = PlanText.clamp(note, to: PlanLimits.maxNotesLength)
        if let rest = restOverrideSeconds, rest <= 0 || rest > PlanLimits.maxRestSeconds {
            result.restOverrideSeconds = rest <= 0 ? nil : PlanLimits.maxRestSeconds
        }
        result.sets = sets.map { $0.sanitised() }
        return result
    }
}

extension PlanSet {
    /// Applies every per-set clamp: an unrecognised `kind` becomes "working"; non-positive rep
    /// targets are dropped and a crossed rep range is swapped back into order; a negative or
    /// non-finite target weight is dropped; `targetRPE` clamps to 1...10; a non-positive
    /// `targetSeconds` is dropped.
    func sanitised() -> PlanSet {
        var result = self
        if SetKind(rawValue: result.kind) == nil {
            result.kind = SetKind.working.rawValue
        }
        if let reps = result.targetReps, reps < 1 { result.targetReps = nil }
        if let high = result.targetRepsHigh, high < 1 { result.targetRepsHigh = nil }
        if let low = result.targetReps, let high = result.targetRepsHigh, high < low {
            result.targetReps = high
            result.targetRepsHigh = low
        }
        if let weight = result.targetWeightKg, weight < 0 || !weight.isFinite {
            result.targetWeightKg = nil
        }
        if let rpe = result.targetRPE {
            result.targetRPE = rpe.isFinite ? min(max(rpe, 1), 10) : nil
        }
        if let seconds = result.targetSeconds, seconds <= 0 {
            result.targetSeconds = nil
        }
        return result
    }
}

extension PlanProgram {
    /// Clamps the program length to 1...52 weeks, drops day-cycle entries that reference a routine
    /// this document doesn't carry (and caps the cycle's length), and reconciles `programWeeks`
    /// with `weeks`: out-of-range and duplicate indices are dropped, and any week the file never
    /// listed is filled in as a normal week — so a file claiming 4 weeks always arrives with
    /// exactly weeks 1...4 rather than a grid the UI can't lay out.
    func sanitised(routineIDs known: Set<UUID>) -> PlanProgram {
        var result = self
        result.name = PlanText.clamp(name, to: PlanLimits.maxNameLength)
        let days = routineIDs.filter { known.contains($0) }
        result.routineIDs = Array(days.prefix(PlanLimits.maxProgramDays))
        result.weeks = min(max(weeks, 1), PlanLimits.maxProgramWeeks)
        result.programWeeks = Self.reconciled(programWeeks, count: result.weeks)
        return result
    }

    /// The three `ProgramWeekKind` raw values the app understands; duplicated here rather than
    /// depending on the app target, the same way `BackupPreferences` mirrors `Preferences`.
    private static let weekKinds: Set<String> = ["normal", "deload", "rest"]

    private static func reconciled(_ weeks: [PlanProgramWeek], count: Int) -> [PlanProgramWeek] {
        var byIndex: [Int: PlanProgramWeek] = [:]
        for week in weeks where (1...count).contains(week.index) && byIndex[week.index] == nil {
            byIndex[week.index] = PlanProgramWeek(index: week.index, kind: kind(week.kind))
        }
        return (1...count).map { byIndex[$0] ?? PlanProgramWeek(index: $0, kind: "normal") }
    }

    private static func kind(_ raw: String) -> String {
        weekKinds.contains(raw) ? raw : "normal"
    }
}

/// Text and number clamps shared by the sanitisers.
enum PlanText {
    /// Trimmed, with control characters stripped, truncated to `limit` characters.
    static func clamp(_ value: String, to limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = String(trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || scalar == "\n" || scalar == "\t"
        })
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit))
    }
}

enum PlanNumber {
    /// A per-exercise increment: non-finite or non-positive falls back to the app default, and an
    /// absurd one is capped, so a shared plan can't set a 10^9 kg jump.
    static func increment(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 2.5 }
        return min(value, PlanLimits.maxIncrementKg)
    }

    /// A rest default in seconds. 0 is a real value — "use the app's default rest" — and passes
    /// through, so a shared exercise keeps "Default" rather than becoming a 150 s override.
    /// Negative falls back to 0 (the same "Default"), absurd is capped.
    static func rest(_ value: Int) -> Int {
        guard value >= 0 else { return 0 }
        return min(value, PlanLimits.maxRestSeconds)
    }
}
