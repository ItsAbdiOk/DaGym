import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("IntentFormatting")
struct IntentFormattingTests {
    private static let benchID = UUID()
    private static let squatID = UUID()
    private static let candidates = [
        IntentFormatting.ExerciseCandidate(id: benchID, name: "Barbell Bench Press", equipment: "barbell"),
        IntentFormatting.ExerciseCandidate(id: squatID, name: "Barbell Squat", equipment: "barbell")
    ]

    @Test("matching ranks the closer name first")
    func matchingRanksClosestFirst() {
        let results = IntentFormatting.matchingExercises("bench press", in: Self.candidates)
        #expect(results.first?.id == Self.benchID)
    }

    @Test("an empty query returns every candidate")
    func emptyQueryReturnsAll() {
        let results = IntentFormatting.matchingExercises("", in: Self.candidates)
        #expect(Set(results.map(\.id)) == Set(Self.candidates.map(\.id)))
    }

    @Test("a query matching nothing returns no candidates")
    func noMatchReturnsEmpty() {
        let results = IntentFormatting.matchingExercises("xyz not a real lift", in: Self.candidates)
        #expect(results.isEmpty)
    }

    @Test("last session dialog names the line and the weekday")
    func lastSessionDialogFormatsLineAndWeekday() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15 // a Tuesday
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(calendar.date(from: components))
        let dialog = IntentFormatting.lastSessionDialog(
            line: "80 × 8, 8, 7", date: date, calendar: calendar
        )
        #expect(dialog == "Last time: 80 × 8, 8, 7 on Tuesday")
    }

    @Test("last session dialog handles no prior session")
    func lastSessionDialogNoSession() {
        let dialog = IntentFormatting.lastSessionDialog(line: nil, date: nil)
        #expect(dialog == "No sessions logged for that exercise yet.")
    }

    @Test("bodyweight dialog formats in the user's unit")
    func bodyweightDialogFormatsUnit() {
        #expect(IntentFormatting.bodyweightLoggedDialog(kg: 82.5, unit: .kg) == "Logged 82.5 kg.")
        let lbsDialog = IntentFormatting.bodyweightLoggedDialog(kg: WeightUnit.lb.toKg(180), unit: .lb)
        #expect(lbsDialog == "Logged 180 lb.")
    }
}
