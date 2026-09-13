import Foundation

/// Clamps and drops the numbers a hand-edited or buggy `.gymplan` file could otherwise insert
/// straight into `RoutineModel`/`SetTemplateModel` — negative rest, non-positive target reps, a
/// NaN or negative target weight, an inverted rep range, an unknown set kind — plus clearing a
/// superset group a drop has left with a single member. Pure and SwiftData-free so it's testable
/// without a `ModelContainer`; the app layer calls it right after `PlanCodec.decode`.
public extension PlanDocument {
    func sanitised() -> PlanDocument {
        var result = self
        result.routines = routines.map { $0.sanitised() }
        return result
    }
}

extension PlanRoutine {
    /// Clamps `repRangeLow`/`repRangeHigh` to 1...50 and swaps them into order, sanitises every
    /// exercise slot, then clears any `supersetGroup` left with only one surviving member.
    func sanitised() -> PlanRoutine {
        var result = self
        var low = clampedRepRange(repRangeLow)
        var high = clampedRepRange(repRangeHigh)
        if low > high { swap(&low, &high) }
        result.repRangeLow = low
        result.repRangeHigh = high
        result.exercises = Self.clearOrphanSupersets(exercises.map { $0.sanitised() })
        return result
    }

    private func clampedRepRange(_ value: Int) -> Int {
        min(max(value, 1), 50)
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
    /// Drops a non-positive `restOverrideSeconds` and sanitises every set.
    func sanitised() -> PlanRoutineExercise {
        var result = self
        if let rest = restOverrideSeconds, rest <= 0 { result.restOverrideSeconds = nil }
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
            result.targetRPE = min(max(rpe, 1), 10)
        }
        if let seconds = result.targetSeconds, seconds <= 0 {
            result.targetSeconds = nil
        }
        return result
    }
}
