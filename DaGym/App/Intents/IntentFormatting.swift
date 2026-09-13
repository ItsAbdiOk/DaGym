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
}
