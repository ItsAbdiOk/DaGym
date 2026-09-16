import Foundation
import GymCore

@testable import DaGym

/// One scripted lifter for the coach eval: who they are, what they have done and what they
/// ask. `seed` fills a fresh builder with their history; the scorer's expectations sit beside
/// it so the report can say what "good" meant for this case.
struct CoachEvalScenario {
    var id: String
    var title: String
    var prompt: String
    var goal: TrainingGoal?
    var experience: ExperienceLevel?
    var weeklyGoal: Int
    /// How many times a week a lone proposed routine would be performed (a two-day full-body
    /// plan runs its one routine twice). Programs carry their own `days_per_week`.
    var sessionsPerWeek: Double
    var volumeExpectation: CoachEvalScoring.VolumeExpectation
    /// Where a proposed weight may sit against the recent best, percent.
    var weightBand: ClosedRange<Double> = CoachEvalScoring.acceptableDeviationPercent
    /// How far back "recent best" looks.
    var bestsWindowDays: Double = 28
    /// Whether the request should end in a `propose_*` card (a forecast question should not).
    var expectsProposal = true
    /// Keyword groups the reply is expected to touch — a heuristic for "cited the evidence".
    var evidenceKeywords: [[String]]
    var seed: @MainActor (CoachEvalStoreBuilder) throws -> Void
}

/// Library names the scenarios log against, spelt as the seed spells them.
enum CoachEvalLift {
    static let bench = "Barbell Bench Press - Medium Grip"
    static let squat = "Barbell Squat"
    static let deadlift = "Barbell Deadlift"
    static let row = "Bent Over Barbell Row"
    static let press = "Standing Military Press"
    static let rdl = "Romanian Deadlift"
    static let pulldown = "Wide-Grip Lat Pulldown"
    static let legPress = "Leg Press"
    static let legCurl = "Lying Leg Curls"
    static let curl = "Barbell Curl"
    static let pushdown = "Triceps Pushdown"
    static let lateralRaise = "Side Lateral Raise"
    static let dbBench = "Dumbbell Bench Press"
    static let dbPress = "Dumbbell Shoulder Press"
    static let dbRow = "One-Arm Dumbbell Row"
    static let goblet = "Dumbbell Goblet Squat"
    static let dbRDL = "Dumbbell Romanian Deadlift"
    static let dbLunge = "Dumbbell Lunges"
    static let bandPullApart = "Band Pull Apart"
    static let pushUp = "Pushups"

    static let gymEquipment = ["barbell", "dumbbell", "machine", "cable", "bodyweight"]
    static let homeEquipment = ["dumbbell", "bands", "bodyweight"]
}

extension CoachEvalStoreBuilder {
    /// `weeks` weeks of the same weekly plan, oldest first, `dayShifts` days before the end of
    /// each week (week 0 ends at `now`). `entries(week, day)` returns the day's session with
    /// the progression baked in; `minutes(week)` and the title follow the day.
    /// With `saveRoutines`, one routine per title (planned from the newest week's sets) and a
    /// weekly schedule on the days the sessions fell — the lifter who follows a plan, so the
    /// deload and swap tools have something to act on.
    func weeks(
        _ weeks: Int, dayShifts: [Double], titles: [String], minutes: (Int) -> Int = { _ in 60 },
        saveRoutines: Bool = false, entries: (_ weekAgo: Int, _ day: Int) -> [Entry]
    ) throws {
        for weekAgo in (0..<weeks).reversed() {
            for (day, shift) in dayShifts.enumerated() {
                try session(
                    daysAgo: Double(weekAgo) * 7 + shift, title: titles[day % titles.count],
                    minutes: minutes(weekAgo), entries: entries(weekAgo, day)
                )
            }
        }
        guard saveRoutines else { return }
        let routines = try titles.enumerated().map { index, title in
            try routine(title, entries: entries(0, index))
        }
        var days: [Weekday: UUID] = [:]
        for (day, shift) in dayShifts.enumerated() {
            let date = now.addingTimeInterval(-shift * 86_400)
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else { continue }
            days[weekday] = routines[day % routines.count].id
        }
        store.saveSchedule(WeeklySchedule(days: days))
    }
}
