import Foundation
import GymCore
import SwiftData

@testable import DaGym

/// An in-memory store with the real exercise library, filled with a scripted lifter's history
/// relative to a fixed `now`. Sessions are written the way `SampleDataSeeder` writes them —
/// straight into the model graph as finished, backfilled workouts — and every working set is
/// also kept as a `CoachEvalScoring.HistorySet` so the scorer reads the same numbers the
/// model does.
@MainActor
final class CoachEvalStoreBuilder {
    let store: WorkoutStore
    /// Tuesday 2026-09-15, midday UTC.
    let now: Date
    let calendar: Calendar
    private(set) var history: [CoachEvalScoring.HistorySet] = []
    private var exercisesByName: [String: ExerciseModel] = [:]

    struct MissingExercise: Error, CustomStringConvertible {
        var name: String
        var description: String { "No library exercise named '\(name)'" }
    }

    /// One logged set: weight, reps and the effort it was logged at.
    struct SetLog {
        var kg: Double
        var reps: Int
        var rpe: Double?
    }

    /// One exercise in a session.
    struct Entry {
        var name: String
        var sets: [SetLog]

        /// `count` identical working sets.
        init(_ name: String, count: Int, kg: Double, reps: Int, rpe: Double? = nil) {
            self.name = name
            sets = (0..<count).map { _ in SetLog(kg: kg, reps: reps, rpe: rpe) }
        }
    }

    init() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        store = WorkoutStore(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)) ?? Date()
    }

    // MARK: - Library

    func exercise(_ name: String) throws -> ExerciseModel {
        if let cached = exercisesByName[name] { return cached }
        let catalogue = store.exerciseCatalogue()
        guard let model = catalogue.models.first(where: { $0.name == name }) else {
            throw MissingExercise(name: name)
        }
        exercisesByName[name] = model
        return model
    }

    func muscles(of model: ExerciseModel) -> [Muscle] {
        model.primaryMuscles.compactMap(Muscle.init(rawValue:))
    }

    // MARK: - Profile and routines

    @discardableResult
    func profile(
        name: String, equipment: [String], restrictsMachines: Bool = false, machines: [String] = []
    ) -> EquipmentProfileInfo {
        store.createProfile(
            name: name, isActive: true, availableEquipment: equipment, plateStock: PlateStock.standardKg,
            restrictsMachines: restrictsMachines, availableMachines: machines
        )
    }

    /// A saved routine whose plan mirrors `entries` (weights from the first set of each).
    @discardableResult
    func routine(_ name: String, entries: [Entry]) throws -> RoutineInfo {
        let drafts = try entries.map { entry in
            RoutineExerciseDraft(
                exerciseID: try exercise(entry.name).id,
                sets: entry.sets.map { set in
                    PlannedSetDraft(
                        kind: .working, targetReps: set.reps, targetWeightKg: set.kg > 0 ? set.kg : nil
                    )
                }
            )
        }
        return store.saveRoutine(id: nil, name: name, exercises: drafts)
    }

    // MARK: - History

    /// A finished session `daysAgo` days before `now`, all sets completed.
    func session(daysAgo: Double, title: String, minutes: Int, entries: [Entry]) throws {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        let workout = WorkoutModel(
            title: title, startedAt: date, endedAt: date.addingTimeInterval(TimeInterval(minutes * 60)),
            isBackfilled: true, routineName: title, sourceDevice: "eval"
        )
        store.context.insert(workout)
        for (order, entry) in entries.enumerated() {
            let model = try exercise(entry.name)
            let row = WorkoutExerciseModel(order: order, exercise: model, workout: workout)
            store.context.insert(row)
            for (index, set) in entry.sets.enumerated() {
                store.context.insert(SetLogModel(
                    order: index, kind: SetKind.working.rawValue, weightKg: set.kg, reps: set.reps,
                    rpe: set.rpe, isCompleted: true, completedAt: date, workoutExercise: row
                ))
                history.append(CoachEvalScoring.HistorySet(
                    exercise: model.name, primaryMuscles: muscles(of: model), weightKg: set.kg,
                    reps: set.reps, date: date
                ))
            }
        }
        workout.stampTotals()
    }

    func bodyweight(kg: Double, daysAgo: Double) {
        store.logBodyweight(kg: kg, date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    /// Saves and rebuilds the PR cache so history tools see every session.
    func finish() {
        store.save()
        store.rebuildPersonalRecords()
        store.invalidateExerciseCatalogue()
    }
}
