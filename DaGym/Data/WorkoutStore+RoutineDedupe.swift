import Foundation
import GymCore
import SwiftData

/// The routine half of the CloudKit seed fold — the counterpart of `ExerciseSeeder.dedupe` and
/// `WorkoutStore+EquipmentDedupe`. Lived inside `RoutineSeeder.swift` until the seeder file
/// outgrew the lint cap; the watch target picks it up through its `WorkoutStore*.swift` glob.
extension WorkoutStore {
    /// Folds routines that share an `importedFromID` — starter routines seeded by two devices, or
    /// the same shared plan imported twice — into the *oldest* one (by `id` on a tie, so every
    /// device agrees). Workouts, programs and the schedule that named a removed copy are
    /// re-pointed at the survivor. Returns the number removed.
    ///
    /// An edited copy beats a pristine one, then oldest, not most recently stamped: the other
    /// copy is usually a fresh seed — a second device's first launch, or the re-seed after a
    /// wipe that a backup restore then imports on top of — and a fresh seed is stamped
    /// `updatedAt = now`, so plain "newest wins" handed every one of those folds to the
    /// pristine copy and the user's planned sets, swapped exercises and stall state went with
    /// the tombstone. Plain "oldest wins" lost the inverse case: a January seed never opened on
    /// the old phone against the copy the lifter rebuilt on the new phone before signing into
    /// iCloud. So a copy edited since it was seeded (`routineWasEdited`) outranks one that
    /// wasn't; two edited copies fall back to the most recent edit, two pristine ones to the
    /// oldest (by `id` on a tie, so every device agrees — the rule `ExerciseSeeder.survivesFirst`
    /// and `EquipmentDedupe` use).
    @discardableResult
    func dedupeRoutines() -> Int {
        let models = fetch(FetchDescriptor<RoutineModel>())
        var byImportID: [UUID: [RoutineModel]] = [:]
        for model in models {
            if let importedFromID = model.importedFromID {
                byImportID[importedFromID, default: []].append(model)
            }
        }
        var replacements: [UUID: UUID] = [:]
        var folded = 0
        for group in byImportID.values where group.count > 1 {
            let ordered = group.sorted(by: Self.routineSurvivesFirst)
            let survivor = ordered[0]
            if survivor.mergedIntoID != nil { survivor.mergedIntoID = nil }
            if survivor.mergedAt != nil { survivor.mergedAt = nil }
            for duplicate in ordered.dropFirst() {
                replacements[duplicate.id] = survivor.id
                if foldRoutine(duplicate, into: survivor) { folded += 1 }
            }
        }
        let swept = sweepRoutineTombstones(models)
        if !replacements.isEmpty { repointRoutineReferences(replacements) }
        if folded + swept > 0 || context.hasChanges { save() }
        return folded + swept
    }

    static func routineSurvivesFirst(_ lhs: RoutineModel, _ rhs: RoutineModel) -> Bool {
        let lhsEdited = routineWasEdited(lhs)
        let rhsEdited = routineWasEdited(rhs)
        if lhsEdited != rhsEdited { return lhsEdited }
        if lhsEdited, lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// A routine saved, or trained, since it was seeded. A fresh seed's `updatedAt` is stamped
    /// within milliseconds of its `createdAt`; anything the lifter did to it comes later than
    /// `routineEditSlack`.
    static func routineWasEdited(_ model: RoutineModel) -> Bool {
        model.updatedAt.timeIntervalSince(model.createdAt) > routineEditSlack
    }

    static let routineEditSlack: TimeInterval = 60

    /// Tombstones `duplicate` rather than deleting it, for the same reason
    /// `ExerciseSeeder.dedupe` does: CloudKit delivers a routine's slots after the routine, and
    /// a hard delete left the other device's slots parentless *and* synced the delete back.
    /// The loser's slots are merged into the survivor's — see `mergeProgressionState` — but are
    /// left attached here; the sweep reclaims them with the tombstone once the grace period is
    /// up. Returns whether anything changed, so a settled tombstone stops counting as work.
    private func foldRoutine(_ duplicate: RoutineModel, into survivor: RoutineModel) -> Bool {
        let merged = mergeProgressionState(from: duplicate, into: survivor)
        let changed = duplicate.mergedIntoID != survivor.id || merged
        // The loser's slots are left attached to the tombstone rather than deleted, exactly as
        // `ExerciseSeeder.dedupe` leaves a loser alive: they are the only record of that
        // device's progression until a later pass has merged it, and deleting them through a
        // `.cascade` parent is both destructive and a CloudKit delete that syncs back.
        // Guarded: SwiftData dirties a row on an equal-value write, and a settled tombstone
        // would otherwise cost a save on every remote-change pass.
        if duplicate.mergedIntoID != survivor.id { duplicate.mergedIntoID = survivor.id }
        if duplicate.mergedAt == nil { duplicate.mergedAt = Date() }
        return changed
    }

    /// Carries each losing slot's engine memory (`stallJSON`, `trainingMaxKg`) onto the
    /// survivor's slot for the same exercise: when the survivor's slot has none, or — for the
    /// stall state — when the loser was trained more recently (`persistProgression` stamps
    /// `updatedAt` with the session start), so the survivor being the older *row* never means
    /// keeping the older *judgement*.
    /// Returns whether anything was actually written, so a settled tombstone stops counting as
    /// work on every remote-change pass.
    @discardableResult
    private func mergeProgressionState(from duplicate: RoutineModel, into survivor: RoutineModel) -> Bool {
        let survivorSlots = survivor.exercises ?? []
        let loserIsNewer = duplicate.updatedAt > survivor.updatedAt
        var merged = false
        for slot in duplicate.exercises ?? [] {
            guard let exerciseID = slot.exercise?.id,
                  let target = survivorSlots.first(where: { $0.exercise?.id == exerciseID })
            else { continue }
            let targetBlank = target.stallJSON.isEmpty || target.stallJSON == "{}"
            let slotBlank = slot.stallJSON.isEmpty || slot.stallJSON == "{}"
            if targetBlank || (loserIsNewer && !slotBlank), slot.stallJSON != target.stallJSON {
                target.stallJSON = slot.stallJSON
                merged = true
            }
            if target.trainingMaxKg == nil, slot.trainingMaxKg != nil {
                target.trainingMaxKg = slot.trainingMaxKg
                merged = true
            }
        }
        return merged
    }

    /// Deletes routine tombstones that have been merged for longer than
    /// `ExerciseSeeder.tombstoneGracePeriod` — but only once nothing depends on them.
    ///
    /// Unlike an exercise tombstone, a folded routine keeps its own slots (see `foldRoutine`),
    /// so it is never childless by itself: every slot is dealt with here first. A slot for a
    /// lift the survivor also has is redundant once its progression state has been merged and
    /// is dropped. A slot for a lift the survivor does *not* have is moved across when the
    /// tombstone was edited after the fold — a device that kept training and editing its copy
    /// while it was offline for longer than the grace period — and dropped otherwise (it was
    /// on the losing side of the fold and the user chose the survivor's plan). A workout still
    /// naming the tombstone (again: a late-syncing device) holds the delete until the pass that
    /// follows has re-pointed it. Nothing is ever cascade-deleted through the tombstone.
    private func sweepRoutineTombstones(_ models: [RoutineModel]) -> Int {
        let cutoff = Date().addingTimeInterval(-ExerciseSeeder.tombstoneGracePeriod)
        let byID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var swept = 0
        for model in models {
            guard model.isMergedAway, let mergedAt = model.mergedAt, mergedAt < cutoff
            else { continue }
            let survivor = model.mergedIntoID.flatMap { byID[$0] }.flatMap { $0.isMergedAway ? nil : $0 }
            if let survivor {
                mergeProgressionState(from: model, into: survivor)
                retireSlots(of: model, into: survivor, editedAfterFold: model.updatedAt > mergedAt)
            } else {
                // The survivor is gone too (the user deleted the routine), so there is nothing
                // to carry the slots to — but they still go one by one, not by cascade.
                for slot in model.exercises ?? [] { context.delete(slot) }
            }
            // Read through the relationship, which lags the deletes and moves just made until
            // the context processes them.
            let remaining = (model.exercises ?? []).filter { !$0.isDeleted && $0.routine?.id == model.id }
            guard remaining.isEmpty, !workoutsReference(routineID: model.id) else { continue }
            context.delete(model)
            swept += 1
        }
        return swept
    }

    /// Moves the tombstone's slots for lifts the survivor lacks onto the survivor when
    /// `editedAfterFold`, and deletes every other slot individually.
    private func retireSlots(of tombstone: RoutineModel, into survivor: RoutineModel, editedAfterFold: Bool) {
        var survivorExerciseIDs = Set((survivor.exercises ?? []).compactMap { $0.exercise?.id })
        var nextOrder = ((survivor.exercises ?? []).map(\.order).max() ?? -1) + 1
        for slot in (tombstone.exercises ?? []).sorted(by: { $0.order < $1.order }) {
            if editedAfterFold, let exerciseID = slot.exercise?.id,
               !survivorExerciseIDs.contains(exerciseID) {
                slot.order = nextOrder
                slot.supersetGroup = nil
                slot.routine = survivor
                survivorExerciseIDs.insert(exerciseID)
                nextOrder += 1
            } else {
                context.delete(slot)
            }
        }
    }

    private func workoutsReference(routineID: UUID) -> Bool {
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.routineID == routineID })
        return fetchCount(descriptor) > 0
    }

    private func repointRoutineReferences(_ replacements: [UUID: UUID]) {
        for workout in fetch(FetchDescriptor<WorkoutModel>()) {
            if let routineID = workout.routineID, let survivor = replacements[routineID] {
                workout.routineID = survivor
            }
        }
        let programs = fetch(FetchDescriptor<ProgramModel>())
        for program in programs where program.routineIDs.contains(where: { replacements[$0] != nil }) {
            program.routineIDs = program.routineIDs.map { replacements[$0] ?? $0 }
        }
        // Walked over the list-valued storage, not the single-routine `days`/`overrides` views:
        // those only ever see (and only ever write) a day's *first* routine, so a day planned
        // "Push A + Arms" used to lose "Arms" the moment "Push A" folded. Duplicates that
        // collapse onto the same survivor within one day are also removed.
        var schedule = schedule()
        var changed = false
        for (day, routineIDs) in schedule.dayRoutines {
            let mapped = Self.repointed(routineIDs, replacements)
            if mapped != routineIDs {
                schedule.dayRoutines[day] = mapped.isEmpty ? nil : mapped
                changed = true
            }
        }
        for (key, routineIDs) in schedule.dateOverrides {
            let mapped = Self.repointed(routineIDs, replacements)
            if mapped != routineIDs {
                schedule.dateOverrides[key] = mapped
                changed = true
            }
        }
        if changed { saveSchedule(schedule) }
    }

    /// `routineIDs` with every folded routine swapped for its survivor, order preserved and
    /// any duplicate the swap created collapsed to its first occurrence.
    private static func repointed(_ routineIDs: [UUID], _ replacements: [UUID: UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return routineIDs.map { replacements[$0] ?? $0 }.filter { seen.insert($0).inserted }
    }
}
