import AppIntents
import Foundation
import GymCore
import SwiftData

/// "Last session for an exercise" Siri Shortcut / App Intent (voice-logging-plan.md §6.1
/// `LastSessionIntent`). Runs without opening the app, via the same short-lived store
/// `LogBodyweightIntent` uses.
struct LastSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Last Session"
    static let openAppWhenRun = false

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    static var parameterSummary: some ParameterSummary {
        Summary("What did I do last for \(\.$exercise)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = IntentStoreAccess.makeStore() else {
            return .result(dialog: IntentDialog(stringLiteral: "DaGym isn't available right now."))
        }
        let last = Self.lastSession(exerciseID: exercise.id, store: store)
        let unit = IntentStoreAccess.preferences().weightUnit
        let line = last.map { Self.line(weightKg: $0.weightKg, reps: $0.reps, unit: unit) }
        let dialog = IntentFormatting.lastSessionDialog(line: line, date: last?.date)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    /// The newest finished workout with a completed, stat-counting set of the exercise — the
    /// same workout supplies both the numbers and the date Siri speaks.
    struct LastSession: Equatable {
        var weightKg: Double
        var reps: [Int]
        var date: Date
    }

    /// "176 lb × 8, 8, 7" — the first counted set's weight in the user's unit, then every rep count.
    static func line(weightKg: Double, reps: [Int], unit: WeightUnit) -> String {
        "\(unit.format(kg: weightKg)) \(unit.symbol) × \(reps.map(String.init).joined(separator: ", "))"
    }

    /// One query, for this exercise's rows in finished workouts only — it used to walk every
    /// finished workout newest-first, faulting `exercises` and each row's `exercise`, so an
    /// exercise never trained walked the whole history before Siri answered "nothing yet".
    /// Sorted in memory by the workout's date: a `SortDescriptor` through the optional
    /// `workout` relationship isn't expressible, and the predicate already keeps the result to
    /// this exercise's own sessions.
    @MainActor
    static func lastSession(exerciseID: UUID, store: WorkoutStore) -> LastSession? {
        let predicate = #Predicate<WorkoutExerciseModel> {
            $0.exercise?.id == exerciseID && $0.workout?.endedAt != nil
        }
        var descriptor = FetchDescriptor<WorkoutExerciseModel>(predicate: predicate)
        descriptor.relationshipKeyPathsForPrefetching = [\.workout, \.sets]
        let rows = store.fetch(descriptor)
            .compactMap { row in row.workout.map { (workout: $0, row: row) } }
            .sorted { $0.workout.startedAt > $1.workout.startedAt }
        for (workout, row) in rows {
            let sets = (row.sets ?? [])
                .filter { $0.isCompleted && $0.setKind.countsTowardStats }
                .sorted { $0.order < $1.order }
            guard let first = sets.first else { continue }
            return LastSession(weightKg: first.weightKg, reps: sets.map(\.reps), date: workout.startedAt)
        }
        return nil
    }
}
