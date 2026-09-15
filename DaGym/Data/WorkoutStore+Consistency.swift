import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// One `DayCell` per day for the last `months` months, for the Consistency heatmap.
    func consistencyCells(months: Int = 12, now: Date = Date(), calendar: Calendar = .current) -> [DayCell] {
        guard let from = calendar.date(byAdding: .month, value: -months, to: now) else { return [] }
        let workouts = dailyActivity(since: from)
        return ConsistencyCalendar.cells(workouts: workouts, from: from, to: now, calendar: calendar)
    }

    /// `week`'s headline numbers plus deltas vs. the week before, for the Weekly Recap card and
    /// the Sunday-evening recap notification. `weeklyGoal` is the caller's concern (`Preferences`)
    /// — this only fetches and totals, matching how `Streaks.weekly` is driven elsewhere.
    func weeklyRecap(for week: Date = Date(), weeklyGoal: Int, calendar: Calendar = .current) -> WeeklyRecap {
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: week)?.start,
              let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart),
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else {
            let zero = WeekActivity(workouts: 0, sets: 0, volumeKg: 0, durationMinutes: 0, prs: 0)
            return ConsistencyCalendar.weeklyRecap(
                thisWeek: zero, lastWeek: zero, week: week, weeklyGoal: weeklyGoal, calendar: calendar
            )
        }
        let thisWeek = weekActivity(from: thisWeekStart, to: nextWeekStart)
        let lastWeek = weekActivity(from: lastWeekStart, to: thisWeekStart)
        return ConsistencyCalendar.weeklyRecap(
            thisWeek: thisWeek, lastWeek: lastWeek, week: week, weeklyGoal: weeklyGoal, calendar: calendar
        )
    }

    // MARK: - Helpers

    /// One `(date, sets, minutes)` per finished workout started on or after `since`. Sets counted
    /// are completed, stats-counting sets only — mirrors `WorkoutStore+History.swift`.
    private func dailyActivity(since: Date) -> [(date: Date, sets: Int, minutes: Int)] {
            let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil && $0.startedAt >= since }
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: predicate)
        let workouts = fetch(descriptor)
        return workouts.map { workout in
            (date: workout.startedAt, sets: countedSets(in: workout).count, minutes: minutes(of: workout))
        }
    }

    private func weekActivity(from: Date, to: Date) -> WeekActivity {
        let predicate = #Predicate<WorkoutModel> {
            $0.endedAt != nil && $0.startedAt >= from && $0.startedAt < to
        }
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: predicate)
        let workouts = fetch(descriptor)
        let sets = workouts.reduce(0) { total, workout in total + countedSets(in: workout).count }
        let volumeTotal = workouts.reduce(0.0) { total, workout in total + volume(of: workout) }
        let minutesTotal = workouts.reduce(0) { total, workout in total + minutes(of: workout) }
        return WeekActivity(
            workouts: workouts.count, sets: sets, volumeKg: volumeTotal, durationMinutes: minutesTotal,
            prs: prCount(from: from, to: to)
        )
    }

    private func countedSets(in workout: WorkoutModel) -> [SetLogModel] {
        (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
    }

    /// Weight × reps over counting sets, reading each row's **lifted** load: an assisted row
    /// stores the assistance dialled in as its weight, and counting that as volume put 30 kg of
    /// help × 8 reps into the week's total. See `WorkoutModel.loadedVolumeKg`, the one total
    /// every persisted-side reader shares.
    private func volume(of workout: WorkoutModel) -> Double {
        workout.loadedVolumeKg
    }

    private func minutes(of workout: WorkoutModel) -> Int {
        guard let endedAt = workout.endedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(workout.startedAt) / 60))
    }
}
