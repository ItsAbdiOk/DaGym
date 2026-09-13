import AppIntents
import Foundation
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
        let line = store.lastSessions(exerciseID: exercise.id, limit: 1).first
        let date = Self.lastSessionDate(exerciseID: exercise.id, store: store)
        let dialog = IntentFormatting.lastSessionDialog(line: line, date: date)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    /// `WorkoutStore.lastSessions` returns only the formatted "80 × 8,8,7" line, not the
    /// workout's date — this repeats just enough of its own newest-first lookup to also grab the
    /// date `IntentFormatting.lastSessionDialog` needs for "on Tuesday".
    @MainActor
    private static func lastSessionDate(exerciseID: UUID, store: WorkoutStore) -> Date? {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let workouts = (try? store.context.fetch(descriptor)) ?? []
        return workouts.first { workout in
            (workout.exercises ?? []).contains { $0.exercise?.id == exerciseID }
        }?.startedAt
    }
}
