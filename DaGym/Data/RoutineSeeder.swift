import Foundation
import GymCore
import SwiftData

/// Seeds the starter routines once per store (`SeedStateModel.routinesSeeded`): the
/// Push/Pull/Legs trio ("Push A", "Pull B", "Legs") plus the routines each starter program
/// cycles — Upper/Lower A/B, Full Body A/B/C and 5×5 A/B/C (`StarterProgramKind.routineNames`).
/// A store seeded before the program routines existed gets them on the next launch, as long
/// as none of them is present yet. Exercises are looked up by name against
/// the already seeded exercise library, falling back to the first exercise
/// with the right primary muscle when a specific name isn't present. Each
/// starter carries a fixed `importedFromID` so a copy seeded by another iCloud
/// device folds into this one (`WorkoutStore.dedupeRoutines()`).
///
/// Every starter routine carries an explicit progression rule (plan.md §6.5) so the engine
/// prescribes from the first session on — a routine saved without a rule is pre-filled by
/// position from the last session instead (`WorkoutStore.effectiveRule`). Exercises whose
/// increment or logging style doesn't fit the routine's rule get a per-exercise override
/// (`starterOverride`): lower-body lifts step 5 kg, bodyweight work goes by reps, holds by seconds.
@MainActor
enum RoutineSeeder {
    /// Stable per-starter identities, shared by every install.
    static let starterIDs: [String: UUID] = [
        "Push A": starterID(1), "Pull B": starterID(2), "Legs": starterID(3),
        "Upper A": starterID(4), "Lower A": starterID(5), "Upper B": starterID(6), "Lower B": starterID(7),
        "Full Body A": starterID(8), "Full Body B": starterID(9), "Full Body C": starterID(10),
        "5×5 A": starterID(11), "5×5 B": starterID(12), "5×5 C": starterID(13)
    ]

    /// The routines behind every non-PPL starter program, in seeding order.
    static let programRoutineNames = [
        "Upper A", "Lower A", "Upper B", "Lower B",
        "Full Body A", "Full Body B", "Full Body C",
        "5×5 A", "5×5 B", "5×5 C"
    ]

    private static func starterID(_ index: Int) -> UUID {
        let group = String(format: "%04X", index)
        let node = String(format: "%012X", index)
        return UUID(uuidString: "6D1A5D4E-\(group)-4A00-8000-\(node)") ?? UUID()
    }

    static func seedStarterRoutinesIfNeeded(store: WorkoutStore) {
        let state = SeedState.row(in: store.context)
        defer { store.dedupeRoutines() }
        if !state.routinesSeeded {
            if store.routines().isEmpty {
                let catalogue = store.exerciseCatalogue()
                seedPushA(store: store, catalogue: catalogue)
                seedPullB(store: store, catalogue: catalogue)
                seedLegs(store: store, catalogue: catalogue)
                seedProgramRoutines(store: store, catalogue: catalogue)
            }
            state.routinesSeeded = true
            state.updatedAt = Date()
            store.save()
            return
        }
        seedProgramRoutinesIfMissing(store: store)
    }

    /// Adds the program routines to a store that was seeded before they existed. Only fires when
    /// the store still has routines but none of these, so deleting one (or all) stays deleted.
    private static func seedProgramRoutinesIfMissing(store: WorkoutStore) {
        let programIDs = Set(programRoutineNames.compactMap { starterIDs[$0] })
        let all = (try? store.context.fetch(FetchDescriptor<RoutineModel>())) ?? []
        let models = all.filter { !$0.isMergedAway }
        guard !models.isEmpty else { return }
        let existingNames = Set(models.map(\.name))
        let alreadyThere = models.contains { $0.importedFromID.map(programIDs.contains) ?? false }
            || programRoutineNames.contains(where: existingNames.contains)
        guard !alreadyThere else { return }
        seedProgramRoutines(store: store)
        store.save()
    }

    /// `catalogue` is the library read once for the whole seed; every slot lookup runs against it.
    static func seedProgramRoutines(
        store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue? = nil
    ) {
        let catalogue = catalogue ?? store.exerciseCatalogue()
        for spec in programRoutineSpecs() {
            seed(spec, store: store, catalogue: catalogue)
        }
    }

    static func stamp(_ routine: RoutineInfo, store: WorkoutStore) {
        guard let model = store.fetchRoutineModel(id: routine.id) else { return }
        model.importedFromID = starterIDs[routine.name]
    }

    // MARK: - Push A

    private static func seedPushA(store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue) {
        guard
            let bench = lookup(
                catalogue, "Barbell Bench Press - Medium Grip", fallback: "Bench Press", muscle: .chest
            ),
            let incline = lookup(catalogue, "Incline Dumbbell Press", muscle: .chest),
            let shoulderPress = lookup(catalogue, "Barbell Shoulder Press", muscle: .delts),
            let crossover = lookup(catalogue, "Cable Crossover", muscle: .chest),
            let pushdown = lookup(catalogue, "Triceps Pushdown", muscle: .triceps)
        else { return }

        var pushdownSets = (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) }
        pushdownSets[pushdownSets.count - 1].kind = .drop

        let rule = ProgressionRule.doubleProgression(
            low: 6, high: 8, incrementKg: TrainingConstants.defaultUpperBodyIncrementKg
        )
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: bench.id,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 10),
                    PlannedSetDraft(kind: .warmup, targetReps: 5)
                ] + (0..<3).map { _ in
                    PlannedSetDraft(kind: .working, targetReps: 6, targetRepsHigh: 8, targetRPE: 8)
                },
                overrideRule: starterOverride(for: bench, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: incline.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 10) },
                overrideRule: starterOverride(for: incline, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: shoulderPress.id,
                sets: (0..<4).map { _ in PlannedSetDraft(kind: .working, targetReps: 6) },
                overrideRule: starterOverride(for: shoulderPress, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: crossover.id, supersetGroup: 1,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) },
                overrideRule: starterOverride(for: crossover, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: pushdown.id, supersetGroup: 1, sets: pushdownSets,
                overrideRule: starterOverride(for: pushdown, routineRule: rule)
            )
        ]
        let routine = store.saveRoutine(
            id: nil, name: "Push A", progressionRule: "doubleProgression", repRangeLow: 6, repRangeHigh: 8,
            rule: rule, exercises: exercises
        )
        stamp(routine, store: store)
    }

    // MARK: - Pull B

    private static func seedPullB(store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue) {
        guard
            let deadlift = lookup(catalogue, "Barbell Deadlift", fallback: "Deadlift", muscle: .hams),
            let pullups = lookup(catalogue, "Pullups", fallback: "Pull-Up", muscle: .lats),
            let row = lookup(catalogue, "Bent Over Barbell Row", muscle: .lats),
            let curl = lookup(catalogue, "Dumbbell Bicep Curl", muscle: .biceps)
        else { return }

        let rule = ProgressionRule.linear(incrementKg: TrainingConstants.defaultUpperBodyIncrementKg)
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: deadlift.id,
                sets: [PlannedSetDraft(kind: .warmup, targetReps: 8)]
                    + (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 5) },
                overrideRule: starterOverride(for: deadlift, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: pullups.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) },
                overrideRule: starterOverride(for: pullups, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: row.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) },
                overrideRule: starterOverride(for: row, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: curl.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) },
                overrideRule: starterOverride(for: curl, routineRule: rule)
            )
        ]
        let routine = store.saveRoutine(
            id: nil, name: "Pull B", progressionRule: "linear", rule: rule, exercises: exercises
        )
        stamp(routine, store: store)
    }

    // MARK: - Legs

    private static func seedLegs(store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue) {
        guard
            let squat = lookup(catalogue, "Barbell Squat", fallback: "Squat", muscle: .quads),
            let legCurl = lookup(catalogue, "Lying Leg Curls", fallback: "Leg Curl", muscle: .hams),
            let calfRaise = lookup(
                catalogue, "Standing Calf Raises", fallback: "Calf Raise", muscle: .calves
            ),
            let plank = lookup(catalogue, "Plank", muscle: .abs)
        else { return }

        let rule = ProgressionRule.linear(incrementKg: TrainingConstants.defaultUpperBodyIncrementKg)
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: squat.id,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 8),
                    PlannedSetDraft(kind: .warmup, targetReps: 5)
                ] + (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 5) },
                overrideRule: starterOverride(for: squat, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: legCurl.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 10) },
                overrideRule: starterOverride(for: legCurl, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: calfRaise.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 15) },
                overrideRule: starterOverride(for: calfRaise, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: plank.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetSeconds: 60) },
                overrideRule: starterOverride(for: plank, routineRule: rule)
            )
        ]
        let routine = store.saveRoutine(
            id: nil, name: "Legs", progressionRule: "linear", rule: rule, exercises: exercises
        )
        stamp(routine, store: store)
    }

    // MARK: - Overrides

    /// The per-exercise rule a starter routine's weight-based rule can't express: bodyweight
    /// reps, timed holds, assisted work, and any lift whose seeded increment isn't the routine's
    /// (lower-body lifts step `TrainingConstants.defaultLowerBodyIncrementKg`, dumbbells 2 kg) —
    /// those keep the routine's rule shape with the exercise's own increment. Nil when the
    /// routine's rule already fits.
    static func starterOverride(
        for exercise: ExerciseInfo, routineRule: ProgressionRule
    ) -> ProgressionRule? {
        switch exercise.loggingStyle {
        case .bodyweightReps, .weightedBodyweight:
            // plan.md §6.1: bodyweight work progresses by reps, then sets — added load is manual.
            return .bodyweight(
                repCeiling: TrainingConstants.bodyweightRepCeiling,
                maxSets: TrainingConstants.bodyweightMaxSets
            )
        case .timedHold:
            return .timed(stepSeconds: TrainingConstants.defaultTimedStepSeconds)
        case .assisted:
            return .assisted(stepKg: TrainingConstants.defaultAssistedStepKg)
        case .cardio:
            return nil
        case .weightReps:
            let increment = starterIncrementKg(for: exercise)
            guard increment > 0 else { return nil }
            switch routineRule {
            case .linear(let incrementKg) where incrementKg != increment:
                return .linear(incrementKg: increment)
            case .doubleProgression(let low, let high, let incrementKg) where incrementKg != increment:
                return .doubleProgression(low: low, high: high, incrementKg: increment)
            default:
                return nil
            }
        }
    }

    /// A lower-body lift seeds with the lower-body default step (5 kg), whatever its library
    /// increment says; everything else keeps the library's own increment (dumbbells 2 kg…).
    static func starterIncrementKg(for exercise: ExerciseInfo) -> Double {
        exercise.primary.contains(where: \.isLowerBody)
            ? TrainingConstants.defaultLowerBodyIncrementKg
            : exercise.incrementKg
    }

    // MARK: - Lookup

    /// Finds an exercise by exact name, falling back to the first search
    /// result for `fallback` (or `name` if no separate fallback is given),
    /// then to the first exercise whose primary muscle matches.
    static func lookup(
        _ catalogue: WorkoutStore.ExerciseCatalogue, _ name: String, fallback: String? = nil, muscle: Muscle
    ) -> ExerciseInfo? {
        let store = catalogue.store
        let candidates = store.exercises(in: catalogue, matching: name)
        if let exact = candidates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        if let first = candidates.first { return first }
        if let fallback, fallback != name {
            let fallbackCandidates = store.exercises(in: catalogue, matching: fallback)
            if let first = fallbackCandidates.first { return first }
        }
        return store.exercises(in: catalogue, muscle: muscle).first { $0.primary.contains(muscle) }
    }
}

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
        let models = (try? context.fetch(FetchDescriptor<RoutineModel>())) ?? []
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
        let count = try? context.fetchCount(
            FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.routineID == routineID })
        )
        return (count ?? 0) > 0
    }

    private func repointRoutineReferences(_ replacements: [UUID: UUID]) {
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []
        for workout in workouts {
            if let routineID = workout.routineID, let survivor = replacements[routineID] {
                workout.routineID = survivor
            }
        }
        let programs = (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []
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
