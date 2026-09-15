import Foundation
import GymCore
import SwiftData

/// Pre-summarised inputs for the on-device coach (plan.md §6.6): the debrief's dozen facts and
/// the four-week review digest. Every number is derived here from what the lifter logged in
/// DaGym — the same store accessors the rule coach reads — and handed to `CoachLanguageModel`
/// as GymCore value types. Nothing HealthKit-derived is touched: `finishedWorkoutModelsNewestFirst`
/// is DaGym's own log, and imported Health workouts live in a separate container.
extension WorkoutStore {
    // MARK: - Debrief

    /// The facts behind `WorkoutSummaryView`'s debrief card, from the session just finished and
    /// the summary `finish` built for it. `previous` is the summary's own "vs last time" workout.
    func debriefFacts(session: WorkoutSession, summary: WorkoutSummary) -> SessionSummaryFacts {
        let done = session.exercises.flatMap(\.sets).filter { $0.isDone && $0.kind.countsTowardStats }
        let skipped = session.exercises.flatMap(\.sets).filter { !$0.isDone && $0.kind.countsTowardStats }
        let belowLast = done.filter { set in
            guard let previousReps = set.previousReps, let previousWeight = set.previousWeightKg else {
                return false
            }
            return set.reps < previousReps && set.weightKg >= previousWeight - 0.01
        }
        let rpes = done.compactMap { $0.effort?.rpe }
        return SessionSummaryFacts(
            title: session.title,
            durationMinutes: max(1, summary.durationSeconds / 60),
            volumeKg: summary.volumeKg,
            previousVolumeKg: summary.previous?.volumeKg,
            setsDone: summary.setsDone,
            previousSetsDone: summary.previous?.setsDone,
            skippedSets: skipped.count,
            setsBelowLast: belowLast.count,
            personalRecords: Array(Set(summary.prs.map(\.exerciseName))).sorted(),
            averageRPE: rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count),
            previousAverageRPE: summary.previous.flatMap { averageRPE(workoutID: $0.workoutID) },
            e1rmUp: summary.e1rmChanges.filter { ($0.current ?? 0) > ($0.previous ?? 0) + 0.5 }.map(\.name),
            e1rmDown: summary.e1rmChanges
                .filter { $0.previous != nil && ($0.current ?? 0) < ($0.previous ?? 0) - 0.5 }
                .map(\.name)
        )
    }

    private func averageRPE(workoutID: UUID) -> Double? {
        guard let workout = fetchWorkoutModel(id: workoutID) else { return nil }
        let rpes = (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .compactMap(\.rpe)
        guard !rpes.isEmpty else { return nil }
        return rpes.reduce(0, +) / Double(rpes.count)
    }

    // MARK: - Review digest

    /// Pool size per coverage-gap muscle — enough to give the review a real choice, small
    /// enough to keep the prompt short.
    private static let reviewPoolPerMuscle = 3

    /// The last `weeks` weeks, summarised for "Review my training": one `LiftDigest` per
    /// programmed lift (from the same `CoachLiftSnapshot`s the rule coach reads), adherence
    /// against the schedule, coverage gaps, and a small add/swap pool for those gaps.
    func trainingDigest(weeks: Int = 4, now: Date = Date(), calendar: Calendar = .current) -> TrainingDigest {
        let input = coachInput(now: now, calendar: calendar)
        let since = calendar.date(byAdding: .weekOfYear, value: -weeks, to: now) ?? now
        let finished = finishedWorkoutModelsNewestFirst().filter { $0.startedAt >= since }
        let models = fetchExerciseModels(ids: Set(input.lifts.compactMap(\.exerciseID)))
        let unit = preferredWeightUnit
        let lifts = input.lifts.compactMap { lift -> LiftDigest? in
            guard let exerciseID = lift.exerciseID else { return nil }
            let sessions = finished.filter { workout in
                (workout.exercises ?? []).contains { $0.exercise?.id == exerciseID }
            }.count
            let change: Double? = lift.e1rmTrend.count >= 2 && (lift.e1rmTrend.first ?? 0) > 0
                ? ((lift.e1rmTrend.last ?? 0) - (lift.e1rmTrend.first ?? 0)) / (lift.e1rmTrend.first ?? 1)
                : nil
            let range = repRange(exerciseID: exerciseID)
            let increment = models[exerciseID].map {
                Self.reviewIncrementKg(for: exerciseInfo(for: $0), unit: unit)
            }
            return LiftDigest(
                id: exerciseID, name: lift.name, e1rmChangeFraction: change, sessions: sessions,
                isStalled: lift.isStalled,
                repLow: range?.low, repHigh: range?.high,
                incrementKg: increment ?? TrainingConstants.defaultUpperBodyIncrementKg
            )
        }
        let adherence = AdherenceSummary.over(
            weeks: weeks, schedule: input.schedule, loggedWorkoutDates: input.loggedWorkoutDates,
            now: now, calendar: calendar
        )
        let gaps = input.trackedMuscles.filter {
            input.muscleSetsInWindow[$0, default: 0] < TrainingConstants.coachMinSetsPerMuscleInWindow
        }
        let programmed = Set(lifts.map(\.id))
        let available = input.equipmentAvailability
        let pool = gaps.flatMap { muscle in
            input.substitutionLibrary
                .filter { candidate in
                    candidate.primary.contains(muscle)
                        && !programmed.contains(candidate.id)
                        && available.allows(candidate)
                }
                .sorted { $0.name < $1.name }
                .prefix(Self.reviewPoolPerMuscle)
        }
        return TrainingDigest(
            weeks: weeks, lifts: lifts, adherencePercent: adherence.percent, coverageGaps: gaps,
            trainingDays: input.schedule.dayRoutines.keys.sorted { $0.rawValue < $1.rawValue }, pool: pool
        )
    }

    /// The step a review-proposed rule climbs this lift by: the same choice the starter routines
    /// and the rule picker make for a hand-built rule — a lower-body lift on the region's
    /// 5 kg / 10 lb, a lb lifter otherwise on a round 5 lb, and a kg lifter on the exercise's
    /// own library increment (dumbbells 2 kg, a cable stack 1 kg…).
    static func reviewIncrementKg(for exercise: ExerciseInfo, unit: WeightUnit) -> Double {
        let isLowerBody = exercise.primary.contains(where: \.isLowerBody)
        switch unit {
        case .kg:
            return isLowerBody ? TrainingConstants.defaultLowerBodyIncrementKg : exercise.incrementKg
        case .lb:
            return unit.toKg(isLowerBody ? 10 : 5)
        }
    }

    /// The lowest working-set rep target across every routine slot for this exercise.
    private func repRange(exerciseID: UUID) -> (low: Int, high: Int)? {
        let slots = fetch(FetchDescriptor<RoutineExerciseModel>())
            .filter { $0.exercise?.id == exerciseID && $0.routine?.isArchived == false }
        let sets = slots.flatMap { $0.plannedSets ?? [] }.filter { $0.setKind.countsTowardStats }
        guard let low = sets.compactMap(\.targetReps).min() else { return nil }
        return (low, sets.compactMap(\.targetRepsHigh).max() ?? low)
    }
}
