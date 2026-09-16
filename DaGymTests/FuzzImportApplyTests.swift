import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Property-style fuzzing of the three *apply* paths — `BackupService.import`,
/// `PlanShareService.importPlan` and `WorkoutImportService.apply` — against an in-memory store.
/// Decoding is fuzzed in `GymCoreTests/Fuzz*`; here the documents are already values, mutated
/// field by field with hostile numbers, empty/huge strings, unknown raw values, duplicate and
/// self-referencing ids, and every import has to leave the store in a state the rest of the app
/// can read: no routine slot without an exercise, no set with a non-finite number, and the
/// follow-on paths (a second import, export, resuming a session) must not trap either.
@MainActor
@Suite("Fuzz: import apply paths", .serialized)
struct FuzzImportApplyTests {
    nonisolated static let iterations = FuzzIterations.count
    nonisolated static let date = Date(timeIntervalSince1970: 1_700_000_000)

    /// xorshift64*, duplicated from `GymCoreTests` (test targets don't share sources).
    struct RNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 0x2545_F491_4F6C_DD1D
        }
        mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
        mutating func bool() -> Bool { next() & 1 == 1 }
        mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }
    }

    nonisolated static let doubles: [Double] = [
        .nan, .infinity, -.infinity, -0.0, 0, -1, 1e308, -1e308, 5e-324, 60, 2.5
    ]
    nonisolated static let ints: [Int] = [.min, .max, -1, 0, 1, 8, 51, 3601, 1_000_000]
    nonisolated static let strings: [String] = [
        "", " ", "\n", "\u{0}", "sprint", "not-a-kind", "🏋️", String(repeating: "x", count: 130),
        String(repeating: "y", count: 100_000), "Squat", "working", "warmup"
    ]

    // MARK: - Invariants

    /// Nothing the import wrote may be unreadable by the rest of the app.
    private func assertStoreInvariants(_ context: ModelContext, label: String) throws {
        for slot in try context.fetch(FetchDescriptor<RoutineExerciseModel>()) {
            #expect(slot.exercise != nil, "routine slot without an exercise: \(label)")
            #expect(slot.routine != nil, "routine slot without a routine: \(label)")
        }
        for entry in try context.fetch(FetchDescriptor<WorkoutExerciseModel>()) {
            #expect(entry.exercise != nil, "workout entry without an exercise: \(label)")
        }
        for set in try context.fetch(FetchDescriptor<SetLogModel>()) {
            #expect(set.weightKg.isFinite, "non-finite weight: \(label)")
            #expect(set.rpe?.isFinite ?? true, "non-finite rpe: \(label)")
            #expect(set.distanceMeters?.isFinite ?? true, "non-finite distance: \(label)")
            #expect(set.workoutExercise != nil, "orphan set: \(label)")
        }
        for set in try context.fetch(FetchDescriptor<PlannedSetModel>()) {
            #expect(set.targetWeightKg?.isFinite ?? true, "non-finite target weight: \(label)")
            #expect(set.targetRPE?.isFinite ?? true, "non-finite target rpe: \(label)")
            #expect(set.targetDistanceMeters?.isFinite ?? true, "non-finite target distance: \(label)")
        }
        // Ids the app keys dictionaries by must be unique within their parent.
        for workout in try context.fetch(FetchDescriptor<WorkoutModel>()) {
            let entries = workout.exercises ?? []
            #expect(Set(entries.map(\.id)).count == entries.count, "duplicate entry ids: \(label)")
            for entry in entries {
                let sets = entry.sets ?? []
                #expect(Set(sets.map(\.id)).count == sets.count, "duplicate set ids: \(label)")
            }
        }
        let routineIDs = try context.fetch(FetchDescriptor<RoutineModel>()).map(\.id)
        #expect(Set(routineIDs).count == routineIDs.count, "duplicate routine ids: \(label)")
    }

    // MARK: - Backup

    @Test("mutated backups import, re-import, export and resume without trapping or breaking invariants")
    func backupApply() throws {
        var rng = RNG(seed: 0xA991_0001)
        let (store, context) = try makeStoreAndContext()
        for iteration in 0..<Self.iterations {
            var document = backupFixture(rng: &rng, custom: "Custom \(iteration)")
            mutate(&document, rng: &rng)
            let label = "backup \(iteration)"
            _ = BackupService.import(document: document, context: context)
            try assertStoreInvariants(context, label: label)
            // The follow-on paths a restore leads to: the same file again (merge), an export, and
            // every unfinished session being resumed and synced.
            _ = BackupService.import(document: document, context: context)
            _ = BackupService.export(context: context)
            for workout in try context.fetch(FetchDescriptor<WorkoutModel>()) where workout.endedAt == nil {
                if let session = store.resumeSession(for: workout.id) { store.sync(session: session) }
            }
            try assertStoreInvariants(context, label: label + " after follow-on")
        }
    }

    /// Regression: two set logs sharing an id in one backup workout used to import verbatim, and
    /// the first `sync(session:)` on that workout trapped in `Dictionary(uniqueKeysWithValues:)`.
    @Test("duplicate set and entry ids inside one backup workout are re-keyed, so resume + sync can't trap")
    func duplicateSetIDsRegression() throws {
        let (store, context) = try makeStoreAndContext()
        var rng = RNG(seed: 1)
        var document = backupFixture(rng: &rng, custom: "Dup")
        document.workouts[0].endedAt = nil
        let sharedSet = UUID()
        document.workouts[0].exercises[0].sets[0].id = sharedSet
        document.workouts[0].exercises[0].sets[1].id = sharedSet
        document.workouts[0].exercises.append(document.workouts[0].exercises[0])
        BackupService.import(document: document, context: context)
        try assertStoreInvariants(context, label: "duplicate set ids")
        let session = try #require(store.resumeSession(for: document.workouts[0].id))
        store.sync(session: session)
        #expect(session.exercises.count == 2)
    }

    /// Regression: a backup carrying the same routine id twice inserted two rows, and the *next*
    /// import trapped building its routine index with `Dictionary(uniqueKeysWithValues:)`.
    @Test("duplicate routine ids in a backup import once, and a second import doesn't trap")
    func duplicateRoutineIDsRegression() throws {
        let (_, context) = try makeStoreAndContext()
        var rng = RNG(seed: 2)
        var document = backupFixture(rng: &rng, custom: "Dup routine")
        document.routines.append(document.routines[0])
        document.workouts.append(document.workouts[0])
        let first = BackupService.import(document: document, context: context)
        #expect(first.routinesImported == 1)
        #expect(first.workoutsImported == 1)
        let second = BackupService.import(document: document, context: context)
        #expect(second.routinesImported == 0)
        try assertStoreInvariants(context, label: "duplicate routine ids")
    }

    // MARK: - Plan

    @Test("mutated plans sanitise and import without trapping or breaking invariants")
    func planApply() throws {
        var rng = RNG(seed: 0xA991_0002)
        let (_, context) = try makeStoreAndContext()
        for iteration in 0..<Self.iterations {
            let routineID = UUID()
            let custom = "Plan custom \(iteration)"
            var document = PlanDocument(
                exportedAt: Self.date, appVersion: "1.0",
                exercises: [PlanExercise(id: UUID(), name: custom)],
                routines: [PlanRoutine(id: routineID, name: "Legs", exercises: [
                    PlanRoutineExercise(order: 0, exerciseName: custom, supersetGroup: 1, sets: [
                        PlanSet(order: 0, kind: "working", targetReps: 8, targetWeightKg: 60)
                    ]),
                    PlanRoutineExercise(order: 1, exerciseSeedID: "no_such_seed", exerciseName: custom)
                ])],
                program: PlanProgram(id: UUID(), name: "Block", weeks: 4, routineIDs: [routineID, routineID])
            )
            for _ in 0..<(1 + rng.int(4)) {
                Self.planMutations[rng.int(Self.planMutations.count)](&document, &rng)
            }
            let sanitised = document.sanitised()
            _ = PlanShareService.importPlan(document: sanitised, context: context, preview: true)
            _ = PlanShareService.importPlan(document: sanitised, context: context)
            _ = PlanShareService.importPlan(document: sanitised, context: context)
            try assertStoreInvariants(context, label: "plan \(iteration)")
        }
    }

    // MARK: - CSV

    @Test("mutated CSV previews apply twice without trapping or breaking invariants")
    func csvApply() throws {
        var rng = RNG(seed: 0xA991_0003)
        let (store, context) = try makeStoreAndContext()
        let header = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight (kg),Reps,Distance,Seconds,"
            + "Notes,Workout Notes,RPE"
        let cells = Self.strings.map { $0.replacingOccurrences(of: "\n", with: " ") }
            + ["1e308", "NaN", "-0", "9223372036854775807", "-1", "inf", "0", "2024-03-11 18:24:00", "1h 5m"]
        for iteration in 0..<Self.iterations {
            var rows: [[String]] = []
            for row in 0..<(1 + rng.int(6)) {
                var fields = [
                    "2024-03-1\(row % 9) 18:24:00", "Push", "1h", "Custom lift \(iteration)", "\(row)", "60",
                    "8", "0", "0", "", "", "8"
                ]
                for _ in 0..<rng.int(3) { fields[rng.int(fields.count)] = rng.pick(cells) }
                rows.append(fields)
            }
            let csv = ([header] + rows.map { $0.joined(separator: ",") }).joined(separator: "\n") + "\n"
            guard let preview = WorkoutImportService.preview(csv: csv, store: store) else { continue }
            _ = WorkoutImportService.apply(preview: preview, store: store)
            _ = WorkoutImportService.apply(preview: preview, store: store)
            try assertStoreInvariants(context, label: "csv \(iteration)")
        }
    }
}

// MARK: - Fixtures and mutation vocabularies

extension FuzzImportApplyTests {
    // MARK: - Backup fixtures

    private func backupFixture(rng: inout RNG, custom: String) -> BackupDocument {
        let routineID = UUID()
        let set = BackupSetLog(
            id: UUID(), order: 0, kind: "working", weightKg: 60, reps: 8, durationSeconds: 30,
            distanceMeters: 1000, assistanceKg: 5, rpe: 8, isCompleted: true, completedAt: Self.date
        )
        let planned = BackupPlannedSet(
            order: 0, kind: "working", targetReps: 8, targetRepsHigh: 12, targetWeightKg: 60, targetRPE: 8
        )
        return BackupDocument(
            exportedAt: Self.date, appVersion: "1.0",
            exercises: [BackupExercise(id: UUID(), name: custom, isCustom: true, createdAt: Self.date)],
            routines: [BackupRoutine(
                id: routineID, name: "Legs", createdAt: Self.date, updatedAt: Self.date,
                exercises: [BackupRoutineExercise(
                    order: 0, exerciseName: custom, supersetGroup: 1, restOverrideSeconds: 90,
                    plannedSets: [planned, planned]
                )]
            )],
            workouts: [BackupWorkout(
                id: UUID(), title: "Legs", startedAt: Self.date,
                endedAt: rng.bool() ? Self.date.addingTimeInterval(3600) : nil, routineID: routineID,
                routineName: "Legs", bodyweightKg: 80,
                exercises: [BackupWorkoutExercise(
                    id: UUID(), order: 0, routineID: routineID, exerciseName: custom, sets: [set, set]
                )]
            )],
            bodyMeasurements: [BackupBodyMeasurement(id: UUID(), date: Self.date, bodyweightKg: 80)],
            equipmentProfiles: [BackupEquipmentProfile(
                id: UUID(), name: "Gym", isActive: true, plateStockKg: [20, 10], plateCounts: [4, 2]
            )],
            preferences: BackupPreferences(),
            programs: [BackupProgram(
                id: UUID(), name: "Block", weeks: 4, isActive: true, routineIDs: [routineID],
                programWeeks: [BackupProgramWeek(id: UUID(), index: 1, kind: "normal")]
            )],
            achievements: [
                BackupAchievement(id: UUID(), milestoneID: "first", tier: "bronze", earnedAt: Self.date)
            ],
            schedule: BackupSchedule(scheduleJSON: "{}", updatedAt: Self.date),
            exerciseNotes: [BackupExerciseNote(id: UUID(), exerciseName: custom, text: "t")],
            gymCards: [BackupGymCard(id: UUID(), name: "Card", value: "1")],
            coachInteractions: [BackupCoachInteraction(id: UUID(), rule: "r", fingerprint: "f")]
        )
    }

    typealias BackupMutation = @Sendable (inout BackupDocument, inout RNG) -> Void

    /// One hostile edit each; `mutate` applies a handful per document.
    nonisolated private static let backupMutations: [BackupMutation] = exerciseMutations + routineMutations
        + workoutMutations + tableMutations

    nonisolated private static let exerciseMutations: [BackupMutation] = [
        { document, rng in document.exercises[0].name = rng.pick(strings) },
        { document, rng in document.exercises[0].incrementKg = rng.pick(doubles) },
        { document, rng in document.exercises[0].restSeconds = rng.pick(ints) },
        { document, rng in document.exercises[0].seedID = rng.pick(["", "no_such_seed", "\u{0}"]) }
    ]

    nonisolated private static let routineMutations: [BackupMutation] = [
        { document, rng in document.routines[0].exercises[0].exerciseName = rng.pick(strings) },
        { document, rng in
            document.routines[0].exercises[0].plannedSets[0].targetWeightKg = rng.pick(doubles)
        },
        { document, rng in document.routines[0].exercises[0].plannedSets[0].kind = rng.pick(strings) },
        { document, rng in document.routines[0].repRangeLow = rng.pick(ints) },
        { document, _ in document.routines.append(document.routines[0]) }
    ]

    nonisolated private static let workoutMutations: [BackupMutation] = [
        { document, rng in document.workouts[0].exercises[0].sets[0].weightKg = rng.pick(doubles) },
        { document, rng in document.workouts[0].exercises[0].sets[0].reps = rng.pick(ints) },
        { document, rng in document.workouts[0].exercises[0].sets[0].rpe = rng.pick(doubles) },
        { document, rng in
            let custom = document.exercises[0].name
            document.workouts[0].exercises[0].exerciseName = rng.pick(strings + [custom])
        },
        { document, rng in
            document.workouts[0].exercises[0].exerciseSeedID = rng.pick(["", "no_such_seed"])
        },
        { document, rng in document.workouts[0].endedAt = rng.bool() ? date.addingTimeInterval(-1e12) : nil },
        { document, _ in document.workouts.append(document.workouts[0]) }
    ]

    nonisolated private static let tableMutations: [BackupMutation] = [
        { document, rng in document.programs?[0].weeks = rng.pick(ints) },
        { document, _ in document.programs?[0].routineIDs = [UUID(), UUID()] },
        { document, rng in document.equipmentProfiles[0].plateCounts = rng.pick([[], [.max], [-1, -1, -1]]) },
        { document, rng in
            document.schedule = BackupSchedule(scheduleJSON: rng.pick(strings), updatedAt: date)
        }
    ]

    private func mutate(_ document: inout BackupDocument, rng: inout RNG) {
        for _ in 0..<(1 + rng.int(5)) {
            Self.backupMutations[rng.int(Self.backupMutations.count)](&document, &rng)
        }
    }

    nonisolated private static let planMutations: [@Sendable (inout PlanDocument, inout RNG) -> Void] = [
        { document, rng in document.exercises[0].name = rng.pick(strings) },
        { document, rng in document.exercises[0].incrementKg = rng.pick(doubles) },
        { document, rng in document.routines[0].exercises[0].exerciseName = rng.pick(strings) },
        { document, rng in document.routines[0].exercises[0].sets[0].targetWeightKg = rng.pick(doubles) },
        { document, rng in document.routines[0].exercises[0].sets[0].targetRPE = rng.pick(doubles) },
        { document, rng in document.routines[0].exercises[0].sets[0].kind = rng.pick(strings) },
        { document, rng in document.routines[0].repRangeHigh = rng.pick(ints) },
        { document, rng in document.program?.weeks = rng.pick(ints) },
        { document, _ in document.routines.append(document.routines[0]) },
        { document, _ in document.program?.routineIDs = [UUID(), document.routines[0].id] }
    ]
}
