import Foundation
import Testing

@testable import GymCore

/// "Round trip preserves every field" used to mean a hand-written list of fourteen `#expect`s
/// against a document with roughly eighty. A field added to `BackupDocument` and forgotten by
/// `BackupService` — which is exactly how preferences, exercise notes, progress photos, gym cards,
/// coach interactions, the Health tombstones and `excludedFromProgression` all went missing —
/// passed that test without a murmur.
///
/// These two tests are derived from the model instead of from a list:
///
/// 1. **Every property is populated.** A `Mirror` walk over the sample document fails on any
///    `nil` optional or empty array, at any depth. Add an optional field to any `Backup*` type and
///    this fails until the sample sets it — which is the moment to also wire it into the service.
/// 2. **Nothing is lost in a round trip.** Encode → decode → encode must be byte-identical, so a
///    field the sample populates but the codec drops is caught too.
@Suite("BackupDocument coverage")
struct BackupCoverageTests {
    // MARK: - The sample: every field, non-default

    private static let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample() -> BackupDocument {
        BackupDocument(
            formatVersion: BackupDocument.currentFormatVersion, exportedAt: Self.date,
            appVersion: "2.1 (44)", exercises: [exercise()], routines: [routine()],
            workouts: [workout()], bodyMeasurements: [measurement()],
            equipmentProfiles: [equipment()], preferences: preferences(), programs: [program()],
            achievements: [achievement()], schedule: BackupSchedule(
                scheduleJSON: #"{"mon":["push"]}"#, updatedAt: Self.date
            ),
            exerciseNotes: [note()], progressPhotos: [photo()], gymCards: [gymCard()],
            coachInteractions: [coachInteraction()], healthImports: healthImports()
        )
    }

    private func exercise() -> BackupExercise {
        BackupExercise(
            id: UUID(), seedID: "Barbell_Squat", name: "Zercher Squat", primaryMuscles: ["quads"],
            secondaryMuscles: ["glutes"], equipment: "barbell", mechanic: "compound",
            loggingStyle: "weightReps", isPerSide: true, isCustom: true, isFavorite: true,
            barType: "olympic", incrementKg: 5, restSeconds: 210, instructions: "Brace hard.",
            notes: "Elbows hurt.", createdAt: Self.date
        )
    }

    private func routine() -> BackupRoutine {
        BackupRoutine(
            id: UUID(), name: "Legs", notes: "Heavy day", progressionRule: "linear",
            repRangeLow: 4, repRangeHigh: 6, progressionRuleJSON: #"{"linear":{"incrementKg":5}}"#,
            createdAt: Self.date, updatedAt: Self.date, sortOrder: 3, isArchived: true,
            importedFromID: UUID(), symbolName: "figure.strengthtraining.traditional",
            tint: "teal", exercises: [routineExercise()]
        )
    }

    private func routineExercise() -> BackupRoutineExercise {
        BackupRoutineExercise(
            order: 1, exerciseSeedID: "Barbell_Squat", exerciseName: "Zercher Squat",
            supersetGroup: 2, restOverrideSeconds: 180, note: "Pause at the bottom",
            progressionRuleJSON: #"{"linear":{"incrementKg":2.5}}"#, stallJSON: #"{"misses":2}"#,
            trainingMaxKg: 140, excludeFromProgression: true, plannedSets: [plannedSet()]
        )
    }

    private func plannedSet() -> BackupPlannedSet {
        BackupPlannedSet(
            order: 1, kind: "working", targetReps: 5, targetRepsHigh: 8, targetWeightKg: 100,
            targetRPE: 8, targetSeconds: 45
        )
    }

    private func workout() -> BackupWorkout {
        BackupWorkout(
            id: UUID(), title: "Legs", startedAt: Self.date,
            endedAt: Self.date.addingTimeInterval(3600), notes: "Good session", isBackfilled: true,
            routineID: UUID(), routineName: "Legs", bodyweightKg: 82.5, sourceDevice: "iPhone",
            healthKitID: UUID().uuidString, exercises: [workoutExercise()]
        )
    }

    private func workoutExercise() -> BackupWorkoutExercise {
        BackupWorkoutExercise(
            id: UUID(), order: 1, supersetGroup: 2, note: "Felt strong", wasSubstitution: true,
            wasPlannedDeload: true, excludedFromProgression: true, routineID: UUID(),
            exerciseSeedID: "Barbell_Squat", exerciseName: "Zercher Squat", sets: [setLog()]
        )
    }

    private func setLog() -> BackupSetLog {
        BackupSetLog(
            id: UUID(), order: 1, kind: "working", weightKg: 100, reps: 5, durationSeconds: 45,
            distanceMeters: 400, assistanceKg: 10, rpe: 8, isCompleted: true, completedAt: Self.date,
            prescriptionReason: "linear +2.5 kg"
        )
    }

    private func measurement() -> BackupBodyMeasurement {
        BackupBodyMeasurement(id: UUID(), date: Self.date, bodyweightKg: 82.5, source: "health")
    }

    private func equipment() -> BackupEquipmentProfile {
        BackupEquipmentProfile(
            id: UUID(), name: "Home", isActive: true, barKg: 20,
            availableEquipment: ["barbell"], plateStockKg: [20, 10], plateCounts: [4, 4],
            collarsKg: 2.5, createdAt: Self.date, seedKey: "home"
        )
    }

    private func program() -> BackupProgram {
        BackupProgram(
            id: UUID(), name: "PPL", weeks: 4, startedAt: Self.date, completedAt: Self.date,
            isActive: true, routineIDs: [UUID()], createdAt: Self.date,
            programWeeks: [BackupProgramWeek(id: UUID(), index: 1, kind: "deload")]
        )
    }

    private func achievement() -> BackupAchievement {
        BackupAchievement(
            id: UUID(), milestoneID: "first-workout", tier: "gold", earnedAt: Self.date,
            workoutID: UUID()
        )
    }

    private func note() -> BackupExerciseNote {
        BackupExerciseNote(
            id: UUID(), exerciseSeedID: "Barbell_Squat", exerciseName: "Zercher Squat",
            text: "Shoes off", scope: "always", createdAt: Self.date, workoutID: UUID()
        )
    }

    private func photo() -> BackupProgressPhoto {
        BackupProgressPhoto(
            id: UUID(), date: Self.date, pose: "side", bodyweightKg: 82.5, notes: "Week 4",
            imageBase64: Data("jpeg-bytes".utf8).base64EncodedString()
        )
    }

    private func gymCard() -> BackupGymCard {
        BackupGymCard(
            id: UUID(), name: "PureGym", value: "123456789", symbology: "code128", sortOrder: 1,
            createdAt: Self.date, lastUsedAt: Self.date
        )
    }

    private func coachInteraction() -> BackupCoachInteraction {
        BackupCoachInteraction(
            id: UUID(), rule: "stalledLift", fingerprint: "abc123", outcome: "approved",
            date: Self.date
        )
    }

    private func healthImports() -> BackupHealthImport {
        BackupHealthImport(
            imported: [
                BackupImportedHealthWorkout(
                    id: UUID(), healthKitID: UUID().uuidString, title: "Strength",
                    startedAt: Self.date, endedAt: Self.date.addingTimeInterval(3600),
                    importedAt: Self.date
                )
            ],
            ignoredHealthKitIDs: [UUID().uuidString]
        )
    }

    private func preferences() -> BackupPreferences {
        var value = BackupPreferences(
            weightUnit: "lb", effortScale: "rir", defaultRestSeconds: 90, weeklyGoal: 5,
            keepScreenAwake: false, restSound: false, restHaptics: false, restScreenFlash: true,
            weekStartsMonday: false
        )
        value.healthWriteWorkouts = true
        value.healthSyncBodyweight = true
        value.healthReadRecovery = true
        value.healthReadBodyComposition = true
        value.healthImportWorkouts = true
        value.healthAutoImportWorkouts = true
        value.healthEstimateCalories = true
        value.calendarSyncEnabled = true
        value.scheduledStartHour = 7
        value.iCloudSyncEnabled = false
        value.streakRemindersEnabled = true
        value.weeklyRecapEnabled = true
        value.reminderHour = 20
        value.bodyweightGoalKg = 80
        value.lockPhotos = true
        value.hasCompletedOnboarding = true
        value.trainingGoal = "strength"
        value.deloadSnoozedUntil = Self.date
        value.accent = "teal"
        value.compactWorkoutLayout = true
        value.showSetSteppers = true
        value.restPauseSeconds = 25
        value.workoutDayReminderEnabled = true
        value.workoutDayReminderHour = 9
        value.effortTrackingEnabled = false
        value.appearance = "dark"
        value.bodyFigure = "female"
        value.playRestSoundOnSilent = true
        value.weighInBeforeWorkout = true
        value.voiceSpeakBackOnHeadphones = false
        value.voiceAutoLogEnabled = true
        return value
    }

    // MARK: - The two model-derived checks

    @Test("every property of every backup type is populated in the sample")
    func samplePopulatesEveryProperty() {
        let missing = Self.unpopulatedPaths(in: sample(), path: "BackupDocument")
        #expect(
            missing.isEmpty,
            """
            These backup fields are nil or empty in the round-trip sample: \(missing.joined(separator: ", ")).
            A field that isn't in the sample isn't covered by the round-trip test — populate it here,
            and make sure BackupService actually exports and imports it.
            """
        )
    }

    /// A guard that only ever passes is worth nothing — this proves the walk fails when it should.
    @Test("the coverage walk actually reports a field left unset")
    func coverageWalkDetectsMissingField() {
        var document = sample()
        document.progressPhotos?[0].imageBase64 = nil
        document.preferences.voiceAutoLogEnabled = nil
        document.workouts[0].exercises[0].routineID = nil
        document.gymCards = []
        let missing = Self.unpopulatedPaths(in: document, path: "BackupDocument")
        #expect(missing.contains { $0.hasSuffix("imageBase64") })
        #expect(missing.contains { $0.hasSuffix("voiceAutoLogEnabled") })
        #expect(missing.contains { $0.hasSuffix("routineID") })
        #expect(missing.contains { $0.contains("gymCards") })
    }

    @Test("encode → decode → encode is byte-identical, so no populated field is lost")
    func roundTripLosesNothing() throws {
        let encoded = try BackupCodec.encode(sample())
        let decoded = try BackupCodec.decode(encoded)
        let reencoded = try BackupCodec.encode(decoded)
        #expect(encoded == reencoded)
    }

    @Test("the decoded document still reads back its own values")
    func decodedValuesSurvive() throws {
        let document = sample()
        let decoded = try BackupCodec.decode(try BackupCodec.encode(document))
        #expect(decoded.preferences.weightUnit == "lb")
        #expect(decoded.preferences.voiceAutoLogEnabled == true)
        #expect(decoded.preferences.bodyweightGoalKg == 80)
        #expect(decoded.workouts.first?.exercises.first?.excludedFromProgression == true)
        #expect(decoded.workouts.first?.exercises.first?.routineID
            == document.workouts.first?.exercises.first?.routineID)
        #expect(decoded.progressPhotos?.first?.imageBase64 != nil)
        #expect(decoded.healthImports?.ignoredHealthKitIDs.count == 1)
        #expect(decoded.exerciseNotes?.first?.scope == "always")
        #expect(decoded.gymCards?.first?.symbology == "code128")
        #expect(decoded.coachInteractions?.first?.outcome == "approved")
    }

    @Test("an older export with none of the new sections still decodes")
    func olderExportStillDecodes() throws {
        let old = BackupDocument(
            exportedAt: Self.date, appVersion: "1.0 (1)", preferences: BackupPreferences()
        )
        let decoded = try BackupCodec.decode(try BackupCodec.encode(old))
        #expect(decoded.exerciseNotes == nil)
        #expect(decoded.progressPhotos == nil)
        #expect(decoded.healthImports == nil)
        #expect(decoded.preferences.voiceAutoLogEnabled == nil)
    }

    // MARK: - Mirror walk

    /// Every path under `value` that is a nil optional or an empty collection. Reflection, not a
    /// list, so it grows with the model on its own.
    private static func unpopulatedPaths(in value: Any, path: String) -> [String] {
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            guard let wrapped = mirror.children.first?.value else { return [path] }
            return unpopulatedPaths(in: wrapped, path: path)
        case .collection:
            guard let first = mirror.children.first?.value else { return ["\(path) (empty)"] }
            return unpopulatedPaths(in: first, path: "\(path)[0]")
        case .struct, .class:
            // Leaf value types reflect as structs with children we don't want to descend into.
            guard !isLeaf(value) else { return [] }
            return mirror.children.flatMap { child in
                unpopulatedPaths(in: child.value, path: "\(path).\(child.label ?? "?")")
            }
        default:
            return []
        }
    }

    private static func isLeaf(_ value: Any) -> Bool {
        value is Date || value is UUID || value is String || value is Data
    }
}
