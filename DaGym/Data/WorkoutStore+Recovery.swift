import Foundation
import GymCore
import SwiftData

/// One muscle's recovery state for the Recovery map screen: how spent it is,
/// when it'll be fresh again, and which recent exercises fatigued it.
struct MuscleRecovery: Identifiable {
    var id: Muscle { muscle }
    var muscle: Muscle
    /// Raw `GymCore.Recovery.fatigue` value.
    var fatigue: Double
    /// 0 (fresh) … 1 (spent) — `GymCore.Recovery.map`'s value for this muscle.
    var spent: Double
    /// When this muscle drops back under the "still spent" threshold. Nil
    /// means it's already there.
    var recoveredBy: Date?
    /// Up to the 3 most recent contributing exercises, newest first.
    var contributors: [Contributor]

    struct Contributor: Identifiable, Hashable {
        var id: String { "\(exerciseName)-\(date.timeIntervalSince1970)" }
        var exerciseName: String
        var sets: Int
        var date: Date
    }
}

/// Recovery + balance snapshot for `RecoveryMapView`, built from the last 7
/// days of finished, non-warm-up sets.
struct RecoverySnapshot {
    /// Fresh → spent, 0…1, for the body map. Only muscles with events appear.
    var map: [Muscle: Double]
    /// Every trained muscle, sorted most-spent first.
    var perMuscle: [MuscleRecovery]
    /// Muscles with zero events in the last 7 days, for the "Balance" section.
    var untrainedMuscles: [Muscle]
}

extension WorkoutStore {
    /// Builds `RecoverySnapshot` from `recoveryEvents(since:)` (last 7 days) plus a direct
    /// query for which exercises contributed to each muscle. Warm-ups never contribute —
    /// `recoveryEvents` and the contributor lookup both skip them the same way.
    func recoverySnapshot(now: Date = Date()) -> RecoverySnapshot {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let events = recoveryEvents(since: since)
        let fatigueByMuscle = Recovery.fatigue(events: events, now: now)
        let spentByMuscle = Recovery.map(events: events, now: now)
        let contributorsByMuscle = recoveryContributors(since: since)

        let perMuscle = Muscle.allCases
            .compactMap { muscle -> MuscleRecovery? in
                guard let spent = spentByMuscle[muscle], spent > 0 else { return nil }
                let fatigue = fatigueByMuscle[muscle] ?? 0
                return MuscleRecovery(
                    muscle: muscle, fatigue: fatigue, spent: spent,
                    recoveredBy: recoveredByDate(fatigue: fatigue, muscle: muscle, now: now),
                    contributors: contributorsByMuscle[muscle] ?? []
                )
            }
            .sorted { $0.spent > $1.spent }

        let trained = Set(events.map(\.muscle))
        let untrained = Muscle.allCases.filter { !trained.contains($0) }
            .sorted { $0.displayName < $1.displayName }

        return RecoverySnapshot(map: spentByMuscle, perMuscle: perMuscle, untrainedMuscles: untrained)
    }

    /// When a muscle's fatigue decays back under the same "still spent" threshold used by
    /// `Recovery.headline` (converted from a 0…1 spent score into a raw fatigue value). Nil
    /// once it's already below that line.
    private func recoveredByDate(fatigue: Double, muscle: Muscle, now: Date) -> Date? {
        let fatigueThreshold = Recovery.fatigueThreshold(spent: TrainingConstants.recoveryHeadlineThreshold)
        let interval = Recovery.recoveredBy(
            fatigue: fatigue, tau: muscle.recoveryTimeConstantHours, threshold: fatigueThreshold
        )
        guard interval > 0 else { return nil }
        return now.addingTimeInterval(interval)
    }

    /// Up to 3 most recent (exercise, set count, date) contributions per muscle, from
    /// completed non-warm-up sets of finished workouts since `since`.
    private func recoveryContributors(since: Date) -> [Muscle: [MuscleRecovery.Contributor]] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil && $0.startedAt >= since }
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: predicate)
        let workouts = (try? context.fetch(descriptor)) ?? []
        let raw = workouts.flatMap(rawContributions)

        var grouped: [Muscle: [MuscleRecovery.Contributor]] = [:]
        for muscle in Muscle.allCases {
            let entries = raw.filter { $0.muscle == muscle }
                .sorted { $0.date > $1.date }
                .prefix(3)
                .map {
                    MuscleRecovery.Contributor(exerciseName: $0.exerciseName, sets: $0.sets, date: $0.date)
                }
            if !entries.isEmpty { grouped[muscle] = Array(entries) }
        }
        return grouped
    }

    private struct RawContribution {
        var muscle: Muscle
        var exerciseName: String
        var sets: Int
        var date: Date
    }

    private func rawContributions(in workout: WorkoutModel) -> [RawContribution] {
        (workout.exercises ?? []).flatMap { exerciseModel -> [RawContribution] in
            guard let exercise = exerciseModel.exercise else { return [] }
            let sets = (exerciseModel.sets ?? []).filter { $0.isCompleted && $0.setKind.countsTowardStats }
            guard !sets.isEmpty else { return [] }
            let date = sets.compactMap(\.completedAt).max() ?? workout.startedAt
            return (exercise.primary + exercise.secondary).map { muscle in
                RawContribution(muscle: muscle, exerciseName: exercise.name, sets: sets.count, date: date)
            }
        }
    }
}
