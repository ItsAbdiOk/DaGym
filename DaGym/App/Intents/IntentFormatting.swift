import Foundation
import GymCore

/// Pure formatting/matching helpers shared by the App Intents (`StartWorkoutIntent`,
/// `LogBodyweightIntent`, `LastSessionIntent`, `ExerciseEntityQuery`). Kept free of
/// AppIntents/SwiftData so they're plain, fast unit tests — `DaGymTests/IntentFormattingTests.swift`.
enum IntentFormatting {
    /// One exercise as an intent needs to see it: enough to build an `ExerciseEntity` without
    /// this file depending on AppIntents or the SwiftData model.
    struct ExerciseCandidate: Hashable {
        var id: UUID
        var name: String
        var equipment: String?

        init(id: UUID, name: String, equipment: String? = nil) {
            self.id = id
            self.name = name
            self.equipment = equipment
        }
    }

    /// Ranks `candidates` against `query` using the same fuzzy matcher voice/text logging uses
    /// (`GymCore.ExerciseMatcher`), best match first, dropping anything scoring 0. An empty query
    /// returns every candidate unranked, for `ExerciseEntityQuery.suggestedEntities`-style calls.
    static func matchingExercises(
        _ query: String, in candidates: [ExerciseCandidate]
    ) -> [ExerciseCandidate] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return candidates }
        let library = candidates.map {
            ParseContext.ExerciseCandidate(id: $0.id, name: $0.name, equipment: $0.equipment)
        }
        let context = ParseContext(unit: .kg, library: library)
        // Same floor as the voice plan: below it a name is a guess, and Siri should say
        // "no match" rather than offer unrelated lifts.
        let ranked = ExerciseMatcher.match(query, in: context).filter { $0.score >= 0.6 }
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return ranked.compactMap { byID[$0.id] }
    }

    /// "Last time: 80 × 8, 8, 7 on Tuesday" for `LastSessionIntent`. `nil` line/date means no
    /// session has been logged for that exercise yet.
    static func lastSessionDialog(line: String?, date: Date?, calendar: Calendar = .current) -> String {
        guard let line, let date else { return "No sessions logged for that exercise yet." }
        var weekdayCalendar = calendar
        weekdayCalendar.locale = Locale(identifier: "en_US_POSIX")
        let formatter = DateFormatter()
        formatter.calendar = weekdayCalendar
        formatter.locale = weekdayCalendar.locale
        formatter.dateFormat = "EEEE"
        return "Last time: \(line) on \(formatter.string(from: date))"
    }

    /// "Logged 82.5 kg." for `LogBodyweightIntent`'s confirmation dialog.
    static func bodyweightLoggedDialog(kg: Double, unit: WeightUnit) -> String {
        "Logged \(unit.format(kg: kg)) \(unit.symbol)."
    }

    /// "You're on a 3-week streak, with 2 of 4 workouts this week." for `GetStreakIntent`. A
    /// zero streak is phrased as what's still needed, since "0-week streak" reads as a jibe.
    static func streakDialog(current: Int, thisWeekCount: Int, weeklyGoal: Int) -> String {
        let week = "\(thisWeekCount) of \(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s") this week"
        guard current > 0 else { return "No streak yet — \(week). Hit your goal to start one." }
        return "You're on a \(current)-week streak, with \(week)."
    }

    /// "Starting Push Day A." / "Starting a freestyle workout." for `StartWorkoutIntent`, spoken
    /// as the app opens. `nil` means no routine is scheduled today, and `RootView` really does
    /// start a freestyle session then (`startPendingWorkout`).
    static func startWorkoutDialog(routineName: String?) -> String {
        guard let routineName else { return "Starting a freestyle workout." }
        return "Starting \(routineName)."
    }

    /// "Continuing Push Day A." when a session is already in progress — the intent never
    /// replaces one, so the dialog must not claim to.
    static func continueWorkoutDialog(title: String) -> String {
        "Continuing \(title)."
    }
}
