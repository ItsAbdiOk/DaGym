import Foundation
import GymCore

/// Everything the Progress hub prints, gathered in one store pass per refresh: the three
/// rings, the top / needs-work muscle tiles, the row subtitles and the coverage callout.
/// A plain value so the screen re-renders from it without touching the store.
struct ProgressHubSummary {
    struct MuscleTile {
        var muscle: Muscle
        var detail: String
        /// The "needs work" tile prints its detail in a warm amber; the top muscle stays ink.
        var isWarning = false
    }

    struct Callout {
        var title: String
        var detail: String
        /// What "Fix" writes into the coach's composer: the title as a question.
        var question: String { CoachChatQuestion.coverage(finding: title) }
    }

    var thisWeekCount = 0
    var weeklyGoal = 4
    var volumeKg: Double = 0
    var lastWeekVolumeKg: Double = 0
    /// Mean RPE of this week's rated sets, nil when nothing was rated (ring reads empty).
    var meanRPE: Double?
    var topMuscle: MuscleTile?
    var needsWork: MuscleTile?
    var trackedExercises = 0
    /// "Bench 96 kg · Squat 142 kg" — the two most-logged lifts with an estimated 1RM.
    var headlineLifts: [(name: String, e1rmKg: Double)] = []
    var musclesOnTarget = 0
    var musclesBehind = 0
    var callout: Callout?

    /// Sessions this week against the weekly goal, 0…1.
    var sessionsFraction: Double {
        weeklyGoal > 0 ? min(1, Double(thisWeekCount) / Double(weeklyGoal)) : 0
    }

    /// This week's volume against last week's — a full ring means the lifter has matched last
    /// week. With no last week to compare against, any volume at all fills the ring.
    var volumeFraction: Double {
        guard lastWeekVolumeKg > 0 else { return volumeKg > 0 ? 1 : 0 }
        return min(1, volumeKg / lastWeekVolumeKg)
    }

    /// Mean RPE on the 10-point scale.
    var effortFraction: Double { (meanRPE ?? 0) / 10 }

    @MainActor
    static func make(
        store: WorkoutStore, preferences: Preferences, now: Date = Date()
    ) -> ProgressHubSummary {
        let calendar = preferences.trainingCalendar
        var summary = ProgressHubSummary()
        let body = store.bodySeries(
            weeks: 1, calendar: calendar, balanceWindow: .thisWeek(calendar), now: now
        )
        summary.thisWeekCount = body.thisWeek.workouts
        summary.weeklyGoal = preferences.weeklyGoal
        summary.volumeKg = body.thisWeek.volumeKg
        summary.lastWeekVolumeKg = body.lastWeek.volumeKg
        if preferences.effortTrackingEnabled {
            let effort = store.effortSeries(weeks: 1, calendar: calendar, now: now)
            summary.meanRPE = effort.weeks.last(where: { $0.ratedSets > 0 })?.meanRPE
        }
        let snapshot = store.recoverySnapshot(now: now, calendar: calendar)
        summary.topMuscle = topMuscle(setsPerMuscle: body.setsPerMuscle)
        let coverage = store.bodySeries(
            weeks: 1, calendar: calendar,
            balanceWindow: .days(TrainingConstants.coachCoverageWindowDays), now: now
        )
        let split = coverageSplit(setsPerMuscle: coverage.setsPerMuscle, snapshot: snapshot)
        summary.musclesOnTarget = split.onTarget
        summary.musclesBehind = split.behind
        let gap = widestGap(setsPerMuscle: coverage.setsPerMuscle, snapshot: snapshot)
        summary.callout = gap.map(callout)
        summary.needsWork = needsWork(snapshot: snapshot, gap: gap, now: now)
        let lifts = store.exercises(in: store.exerciseCatalogue()).filter { $0.bestE1RM != nil }
        summary.trackedExercises = lifts.count
        summary.headlineLifts = lifts.sorted { $0.sessions > $1.sessions }.prefix(2)
            .compactMap { lift in lift.bestE1RM.map { (name: lift.name, e1rmKg: $0) } }
        return summary
    }

    /// The most-worked muscle this week — the same window the rings and the Balance map use.
    static func topMuscle(setsPerMuscle: [Muscle: Double]) -> MuscleTile? {
        guard let top = setsPerMuscle.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }), top.value > 0 else { return nil }
        return MuscleTile(muscle: top.key, detail: BalanceMapSection.setsLabel(top.value))
    }

    /// The muscle that has gone longest without work among those the lifter has ever trained —
    /// the same list Balance's "Longest without work" prints, so the two agree. When every
    /// muscle has been worked inside the retention window, the widest coverage gap stands in,
    /// so the tile and the callout below it name the same muscle.
    static func needsWork(snapshot: RecoverySnapshot, gap: CoverageGap?, now: Date) -> MuscleTile? {
        if let rested = snapshot.detrainedMuscles.first(where: { $0.lastTrained != nil }),
           let last = rested.lastTrained {
            let days = max(0, Int(now.timeIntervalSince(last) / 86_400))
            let detail = "\(days) \(days == 1 ? "day" : "days") idle"
            return MuscleTile(muscle: rested.muscle, detail: detail, isWarning: true)
        }
        if let gap {
            let window = TrainingConstants.coachCoverageWindowDays
            let detail = "\(BalanceMapSection.setsLabel(gap.sets)) in \(window) days"
            return MuscleTile(muscle: gap.muscle, detail: detail, isWarning: true)
        }
        guard let untrained = snapshot.untrainedMuscles.first else { return nil }
        return MuscleTile(muscle: untrained, detail: "Not this week", isWarning: true)
    }

    /// Muscles at or above the coach's coverage floor over its window, against those below it.
    /// Only muscles the lifter has ever trained count: a never-trained muscle isn't "behind" a
    /// plan that never included it.
    static func coverageSplit(
        setsPerMuscle: [Muscle: Double], snapshot: RecoverySnapshot
    ) -> (onTarget: Int, behind: Int) {
        let floor = TrainingConstants.coachMinSetsPerMuscleInWindow
        let everTrained = trainedMuscles(setsPerMuscle: setsPerMuscle, snapshot: snapshot)
        let onTarget = everTrained.filter { setsPerMuscle[$0, default: 0] >= floor }.count
        return (onTarget, everTrained.count - onTarget)
    }

    /// Every muscle with a set in the window or a recorded last-trained date.
    private static func trainedMuscles(
        setsPerMuscle: [Muscle: Double], snapshot: RecoverySnapshot
    ) -> Set<Muscle> {
        Set(snapshot.detrainedMuscles.filter { $0.lastTrained != nil }.map(\.muscle))
            .union(setsPerMuscle.filter { $0.value > 0 }.keys)
    }

    /// One under-trained muscle and its set count in the coverage window.
    struct CoverageGap {
        let muscle: Muscle
        let sets: Double
    }

    /// The muscle furthest under the coach's coverage floor, or nil when none is.
    static func widestGap(setsPerMuscle: [Muscle: Double], snapshot: RecoverySnapshot) -> CoverageGap? {
        let floor = TrainingConstants.coachMinSetsPerMuscleInWindow
        // Spelled out with a named type rather than a tuple chain, like `CoachRules`: the
        // inferred map/filter/sorted pipeline pushed the type checker past its time limit.
        var gaps: [CoverageGap] = []
        for muscle in trainedMuscles(setsPerMuscle: setsPerMuscle, snapshot: snapshot) {
            let sets = setsPerMuscle[muscle] ?? 0
            if sets < floor { gaps.append(CoverageGap(muscle: muscle, sets: sets)) }
        }
        gaps.sort { lhs, rhs in
            lhs.sets == rhs.sets ? lhs.muscle.rawValue < rhs.muscle.rawValue : lhs.sets < rhs.sets
        }
        return gaps.first
    }

    /// The widest coverage gap, in the coach's terms: "Biceps have had 2 sets in 14 days".
    static func callout(_ gap: CoverageGap) -> Callout {
        let window = TrainingConstants.coachCoverageWindowDays
        let had = gap.sets == 0 ? "had no sets" : "had \(BalanceMapSection.setsLabel(gap.sets))"
        let verb = gap.muscle.isPlural ? "have" : "has"
        return Callout(
            title: "\(gap.muscle.displayName) \(verb) \(had) in \(window) days",
            detail: "A couple of direct sets this week would close it"
        )
    }
}

extension Muscle {
    /// "Biceps have" / "Chest has" — so a headline about a muscle reads as a sentence.
    var isPlural: Bool { displayName.hasSuffix("s") }
}
