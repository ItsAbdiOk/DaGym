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
    /// When this muscle's reading drops back under the "worked hard recently" line. Nil means
    /// it's already there.
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

/// The words both recovery screens put on a `MuscleRecovery`. Deliberately descriptive: the
/// score is an effort-weighted count of recent sets decaying over time, so the copy talks about
/// how much work the muscle has taken and when that reading eases off — never about what is
/// happening inside the lifter's body, and never as a "% recovered" the number can't support.
extension MuscleRecovery {
    /// How much recent work this muscle has taken. The two band edges are the same constants the
    /// rest of the app already acts on: the recovery headline's "still spent" line and the
    /// coach's recovery-debt line.
    var workloadLabel: String {
        if spent >= TrainingConstants.coachRecoveryDebtThreshold { return "Heavy recent work" }
        if spent >= TrainingConstants.recoveryHeadlineThreshold { return "A lot of recent work" }
        if spent >= TrainingConstants.recoveryHeadlineThreshold / 2 { return "Some recent work" }
        return "Little recent work"
    }

    /// True when there is next to nothing on the muscle: "eased off" would claim a reading that
    /// was never up, so those rows say "Fresh" instead.
    private var isFresh: Bool { spent < TrainingConstants.recoveryHeadlineThreshold / 2 }

    /// Short form for the muscle list row.
    var easesOffLabel: String {
        guard let recoveredBy else { return isFresh ? "Fresh" : "Eased off" }
        return "Eases off \(Self.timingLabel(recoveredBy))"
    }

    /// Long form for the detail sheet.
    var easesOffSentence: String {
        guard let recoveredBy else {
            return isFresh ? "Fresh — little recent work on this muscle" : "This reading has eased off"
        }
        return "Eases off around \(Self.timingLabel(recoveredBy))"
    }

    /// Locale-aware, and never an ambiguous bare weekday: a weekday plus time reads as "this
    /// week", so past six days out it switches to a dated form. The old `"EEE HH:mm"` forced
    /// 24-hour on every locale and printed "Thu" for a Thursday nine days away.
    static func timingLabel(_ date: Date, now: Date = .now) -> String {
        guard date.timeIntervalSince(now) < 6 * 86_400 else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// One muscle's place in the "Balance" section's longest-untrained list. `retention` is
/// `GymCore.Recovery.retention` — a 1.0 → 0.5 function of time since the last counting set, used
/// here purely as the sort key ("3 weeks off ranks above 8 days off"). It is never shown as a
/// number: the screen prints how long it has been, which is the part that is actually known.
struct MuscleRetention: Identifiable, Hashable {
    var id: Muscle { muscle }
    var muscle: Muscle
    var retention: Double
    /// When the last counting set landed on this muscle; nil if it was never trained.
    var lastTrained: Date?
}

/// Recovery + balance snapshot for `RecoveryMapView`, built from the last
/// `WorkoutStore.recoveryWindowDays` days of finished, non-warm-up sets (plus all-time
/// "last trained" dates for the balance list).
struct RecoverySnapshot {
    /// Fresh → spent, 0…1, for the body map. Only muscles with events appear.
    var map: [Muscle: Double]
    /// Every trained muscle, sorted most-spent first.
    var perMuscle: [MuscleRecovery]
    /// Muscles with zero events in the last 7 days, for the "Balance" section.
    var untrainedMuscles: [Muscle]
    /// Muscles untrained long enough to rank (`retention < 1`), longest first, ties in body
    /// order — the graded list behind Balance's "Longest without work".
    var detrainedMuscles: [MuscleRetention] = []
    /// Every muscle's time-since-training score, 1.0 → 0.5 — the sort key behind
    /// `detrainedMuscles`, not something any screen prints.
    var retention: [Muscle: Double] = [:]
}

extension WorkoutStore {
    /// **The** recovery window: days of history every fatigue reading in the app is built from —
    /// Home's card, the Recovery screen, the coach's `CoachInput.recoveryMap` and the
    /// substitution scorer all go through `recoveryMap(now:calendar:)` or `recoverySnapshot`, so
    /// the same muscle can never show two numbers on two screens. Long enough that the slowest
    /// muscle's (τ = 48 h) residual is under 0.1 % of a set at the cutoff: a workout leaving the
    /// window changes nothing anyone can see. `RecoveryMapView` prints this number, so the copy
    /// and the maths can't drift apart.
    static let recoveryWindowDays = 14
    /// Days of history behind the "not trained this week" list. Deliberately *not* the recovery
    /// window: that answers "how much work has this muscle taken", this one answers "did I train
    /// it this week", and the section says "this week" in so many words.
    static let untrainedWindowDays = 7

    /// Start of the recovery window — the one place `now − recoveryWindowDays` is computed.
    static func recoveryWindowStart(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -recoveryWindowDays, to: now) ?? now
    }

    /// Fresh (0) → spent (1) per trained muscle, over the shared recovery window. Home's
    /// recovery card and anything else that only needs the map use this rather than building
    /// their own window: `recoverySnapshot` is the same map plus the per-muscle detail and two
    /// extra fetches Home has no use for.
    func recoveryMap(now: Date = Date(), calendar: Calendar = .current) -> [Muscle: Double] {
        let since = Self.recoveryWindowStart(now: now, calendar: calendar)
        return Recovery.map(events: recoveryEvents(since: since), now: now)
    }

    /// Builds `RecoverySnapshot` from `recoveryEvents(since:)` (the shared recovery window)
    /// plus a direct query for which exercises contributed to each muscle. Warm-ups never contribute —
    /// `recoveryEvents` and the contributor lookup both skip them the same way.
    /// `calendar` is passed in rather than read: the coach adapter feeds this straight into
    /// `CoachInput.recoveryMap`, and a helper that reaches for `Calendar.current` behind a
    /// caller-supplied one makes the "pure over (store, now, calendar)" promise false.
    func recoverySnapshot(now: Date = Date(), calendar: Calendar = .current) -> RecoverySnapshot {
        let since = Self.recoveryWindowStart(now: now, calendar: calendar)
        let untrainedSince = calendar.date(byAdding: .day, value: -Self.untrainedWindowDays, to: now)
        let events = recoveryEvents(since: since)
        let fatigueByMuscle = Recovery.fatigue(events: events, now: now)
        let spentByMuscle = Recovery.map(events: events, now: now)
        let contributorsByMuscle = recoveryContributors(since: since)
        let lastTrained = lastTrainedDates(now: now)
        let retention = Recovery.retention(lastTrained: lastTrained, now: now)
        let detrained = Recovery.detrainedMuscles(retention: retention).map {
            MuscleRetention(muscle: $0.muscle, retention: $0.retention, lastTrained: lastTrained[$0.muscle])
        }

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

        // "Untrained" keeps its 7-day meaning even though the fatigue scan looks back 14.
        let recent = events.filter { event in untrainedSince.map { event.date >= $0 } ?? true }
        let trained = Set(recent.map(\.muscle))
        let untrained = Muscle.allCases.filter { !trained.contains($0) }

        return RecoverySnapshot(
            map: spentByMuscle, perMuscle: perMuscle, untrainedMuscles: untrained,
            detrainedMuscles: detrained, retention: retention
        )
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
        let workouts = fetch(descriptor)
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

    /// Most recent counting set per muscle over all history, for the retention score. Walks
    /// finished workouts newest-first and stops once every muscle has a date.
    private func lastTrainedDates(now: Date) -> [Muscle: Date] {
        var descriptor = FetchDescriptor<WorkoutModel>(
            predicate: #Predicate { $0.endedAt != nil && $0.startedAt <= now },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 400
        let workouts = fetch(descriptor)
        var result: [Muscle: Date] = [:]
        for workout in workouts {
            for contribution in rawContributions(in: workout) where result[contribution.muscle] == nil {
                result[contribution.muscle] = contribution.date
            }
            if result.count == Muscle.allCases.count { break }
        }
        return result
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
