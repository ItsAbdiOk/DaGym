import GymCore
import SwiftUI

// The value types `RootView` presents from — split out of `RootView.swift` so the tab shell
// stays under the lint cap.

/// What the launch-time Resume/Discard prompt shows for the newest workout a crash or
/// force-quit left unfinished (anything older than a day was already purged at launch).
struct UnfinishedWorkoutPrompt: Identifiable, Equatable {
    let id: UUID
    let title: String
    let startedAt: Date
    let setsDone: Int

    /// "Started 25 min ago · 3 sets logged"
    var detail: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let started = formatter.localizedString(for: startedAt, relativeTo: Date())
        let sets = setsDone == 1 ? "1 set logged" : "\(setsDone) sets logged"
        return "Started \(started) · \(sets)"
    }

    /// The newest unfinished workout, or `nil` when there is nothing to resume.
    @MainActor
    static func newest(in store: WorkoutStore) -> UnfinishedWorkoutPrompt? {
        guard let model = store.unfinishedWorkouts().first else { return nil }
        let setsDone = (model.exercises ?? []).flatMap { $0.sets ?? [] }.filter(\.isCompleted).count
        return UnfinishedWorkoutPrompt(
            id: model.id, title: model.title.isEmpty ? "Workout" : model.title, startedAt: model.startedAt,
            setsDone: setsDone
        )
    }
}

/// `sheet(item:)` needs `Identifiable`; a document's export timestamp is a fine key since two
/// files opened back-to-back are always distinguishable by when they were made.
extension PlanDocument: @retroactive Identifiable {
    public var id: Date { exportedAt }
}

/// Wraps a `WorkoutSummary` (not itself `Identifiable`) for `fullScreenCover(item:)`.
struct SummaryPresentation: Identifiable {
    let id = UUID()
    let summary: WorkoutSummary
    let title: String
}

extension WorkoutSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
