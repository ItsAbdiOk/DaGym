import Foundation
import GymCore
import SwiftData

/// A suggested deload, for the Home "why a deload?" card.
struct DeloadSuggestionInfo: Hashable {
    var reason: String
    /// Stable id of the evidence behind this suggestion (`GymCore.DeloadSuggestion.fingerprint`)
    /// — persisted when the user dismisses it so the same evidence isn't shown again.
    var fingerprint: String
}

extension WorkoutStore {
    /// A suggested deload from stalls, e1RM regression, rising RPE at the same load, or
    /// accumulated hard weeks across the main lifts (plan.md §6.5) — nil when nothing warrants
    /// one, the user snoozed it (`snoozedUntil` is `Preferences.deloadSnoozedUntil`), or its
    /// evidence exactly matches `dismissedFingerprint` (`Preferences.deloadDismissedFingerprint`).
    func deloadSuggestion(
        snoozedUntil: Date?, dismissedFingerprint: String? = nil, weeklyGoal: Int = 4
    ) -> DeloadSuggestionInfo? {
        if let snoozedUntil, snoozedUntil > Date() { return nil }
        let suggestion = DeloadDetector.evaluate(
            lifts: mainLiftSnapshots(), hardWeeks: hardWeekStreak(weeklyGoal: weeklyGoal)
        )
        guard let suggestion else { return nil }
        guard suggestion.fingerprint != dismissedFingerprint else { return nil }
        return DeloadSuggestionInfo(reason: suggestion.reason, fingerprint: suggestion.fingerprint)
    }

    /// "Plan a deload week": creates and immediately starts a one-week program that flags every
    /// current routine's next session as a planned deload (plan.md §6.5's primary action).
    func planDeloadWeek() {
        for other in (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? [] { other.isActive = false }
        let model = ProgramModel(name: "Deload Week", weeks: 1, startedAt: Date(), isActive: true)
        model.routineIDs = routines().map(\.id)
        context.insert(model)
        let week = ProgramWeekModel(index: 1, kind: ProgramWeekKind.deload.rawValue, program: model)
        context.insert(week)
        model.programWeeks = [week]
        save()
    }

    // MARK: - Helpers

    /// The main lifts in a fixed order. The suggestion's reason string (and so its dismissable
    /// `fingerprint`) lists lifts in snapshot order, so this must not depend on dictionary or
    /// fetch order — otherwise the same evidence would hash differently between two reads and a
    /// dismissal would never stick.
    private static let mainLiftOrder = ["bench", "squat", "deadlift", "ohp"]

    /// Stall count + e1RM/RPE trend per main lift key (bench/squat/deadlift/ohp — the map
    /// `WorkoutStore+Milestones.swift` uses), from whichever routine exercise trains each one,
    /// in `mainLiftOrder`.
    private func mainLiftSnapshots() -> [LiftSnapshot] {
        let routineExercises = (try? context.fetch(FetchDescriptor<RoutineExerciseModel>())) ?? []
        var byKey: [String: RoutineExerciseModel] = [:]
        for routineExercise in routineExercises {
            guard let name = routineExercise.exercise?.name, let key = Self.mainLiftKey(name: name) else {
                continue
            }
            byKey[key] = routineExercise
        }
        return Self.mainLiftOrder.compactMap { key in
            byKey[key].flatMap { liftSnapshot(key: key, routineExercise: $0) }
        }
    }

    private func liftSnapshot(key: String, routineExercise: RoutineExerciseModel) -> LiftSnapshot? {
        guard let exerciseID = routineExercise.exercise?.id else { return nil }
        // Fetch extra and filter, then take 3 — a planned deload week's lower numbers are not a
        // decline (`LiftSnapshot.e1rmTrend`'s documented contract), so it must never occupy one
        // of the 3 trend slots.
        let unfiltered = exerciseHistory(exerciseID: exerciseID, limit: 9)
        let history = Array(unfiltered.filter { !$0.wasPlannedDeload }.prefix(3))
        guard !history.isEmpty else { return nil }
        let oldestFirst = history.reversed()
        let e1rms = oldestFirst.compactMap { entry in
            entry.workingSets.compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }.max()
        }
        let rpes = oldestFirst.compactMap { entry in entry.workingSets.first?.effort?.rpe }
        return LiftSnapshot(
            name: key.capitalized, stalls: routineExercise.stallStateValue.consecutiveMisses,
            e1rmTrend: e1rms, rpeAtSameLoadTrend: rpes.isEmpty ? nil : rpes
        )
    }

    /// Consecutive recent weeks (working back from this week) that met `weeklyGoal` with no
    /// planned deload session in them — a simple proxy for "accumulated weeks of hard training
    /// without a lighter week" (A4b: a deload week breaks the streak even if it also hit the
    /// workout count, and the count is the user's actual `Preferences.weeklyGoal`, not a
    /// hard-coded 3).
    private func hardWeekStreak(weeklyGoal: Int) -> Int {
        let calendar = Calendar.current
        var weekCounts: [Date: Int] = [:]
        var weeksWithDeload: Set<Date> = []
        for workout in finishedWorkoutModelsNewestFirst() {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start else {
                continue
            }
            weekCounts[start, default: 0] += 1
            if (workout.exercises ?? []).contains(where: \.wasPlannedDeload) {
                weeksWithDeload.insert(start)
            }
        }
        var streak = 0
        var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        while (weekCounts[cursor] ?? 0) >= max(1, weeklyGoal), !weeksWithDeload.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private static func mainLiftKey(name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("bench press") { return "bench" }
        if lower.contains("squat") { return "squat" }
        if lower.contains("deadlift") { return "deadlift" }
        if lower.contains("overhead press") || lower.contains("shoulder press") { return "ohp" }
        return nil
    }
}
