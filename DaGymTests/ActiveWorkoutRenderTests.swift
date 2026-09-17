import Foundation
import GymCore
import Testing

@testable import DaGym

/// The pure pieces the Active Workout screen renders from — pulled out of `body` so a set edit
/// or a rest tick does less per render.
@MainActor
@Suite("Active workout render helpers")
struct ActiveWorkoutRenderTests {
    private func exercise(_ name: String) -> ExerciseInfo {
        ExerciseInfo(name: name, primary: [.chest], equipment: "Barbell", incrementKg: 2.5, restSeconds: 150)
    }

    @Test("working-set badges count only working sets, in one pass")
    func workingBadgeIndices() {
        let rows = [
            SetEntry(kind: .warmup, weightKg: 40, reps: 10), SetEntry(kind: .working, weightKg: 80, reps: 5),
            SetEntry(kind: .drop, weightKg: 64, reps: 8), SetEntry(kind: .working, weightKg: 80, reps: 5),
            SetEntry(kind: .working, weightKg: 80, reps: 5)
        ]
        let card = WorkoutExerciseEntry(exercise: exercise("Bench"), sets: rows)
        // Same numbers the old per-row prefix count produced: a warm-up before the first
        // working set shows 0, and a drop set repeats the working set above it.
        #expect(card.workingBadgeIndices == [0, 1, 1, 2, 3])
        #expect(WorkoutExerciseEntry(exercise: exercise("Bench"), sets: []).workingBadgeIndices.isEmpty)
    }

    @Test("the header's date label is built once and reads the weekday for a live session only")
    func startedAtLabel() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 13
        components.hour = 10
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))
        let live = WorkoutSession(title: "Push", subtitle: "", startedAt: date, exercises: [])
        // Month and weekday names follow the device locale, so only the shape is pinned:
        // "Sun 13 Sep" — sentence case, no separator, as the redesign's header prints it.
        let label = ActiveWorkoutView.startedAtLabel(for: live)
        #expect(!label.contains(" · "))
        #expect(label.contains("13"))
        #expect(label != label.uppercased())
        #expect(!label.hasPrefix("Backfill"))

        let backfilled = WorkoutSession(
            title: "Push", subtitle: "", startedAt: date, exercises: [], isBackfilled: true
        )
        let backfillLabel = ActiveWorkoutView.startedAtLabel(for: backfilled)
        #expect(backfillLabel.hasPrefix("Backfill · "))
        #expect(backfillLabel.contains("13"))
    }
}
