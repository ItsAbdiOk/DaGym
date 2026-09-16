import Foundation
import GymCore
import SwiftData
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import DaGym

/// The pieces of the Settings section files that are testable without SwiftUI: the backup
/// filename and document, the reset sheet's gate word, and the off-main CSV parse split.
@Suite("Settings sections")
struct SettingsSectionsTests {
    @Test("the export filename is date-stamped with a hoisted formatter")
    func exportFilenameIsDateStamped() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        let date = try #require(Calendar.current.date(from: components))
        #expect(DataSettingsSection.exportFilename(on: date) == "DaGym-backup-2026-09-15")
        // Two calls share the formatter and agree.
        #expect(DataSettingsSection.exportFilename(on: date) == DataSettingsSection.exportFilename(on: date))
    }

    @Test("the backup document keeps the bytes it was built with and only reads JSON")
    func backupFileDocumentKeepsData() {
        let data = Data("{\"formatVersion\":1}".utf8)
        #expect(BackupFileDocument(data: data).data == data)
        #expect(BackupFileDocument.readableContentTypes == [.json])
    }

    @Test("the reset sheet demands the word DELETE")
    func resetSheetGateWord() {
        #expect(ResetAllDataSheet.confirmationWord == "DELETE")
    }
}

/// `ImportSettingsSection` now parses the CSV off the main actor (`WorkoutImport.parse`) and
/// only name-matches on it. That split must produce the same preview the one-call path did.
@MainActor
@Suite("Settings CSV import split")
struct SettingsImportSplitTests {
    private static let csv = [
        "Date,Workout Name,Duration,Exercise Name,Set Order,Weight (kg),Reps,Distance,Seconds,Notes,"
            + "Workout Notes,RPE",
        "2024-03-11 18:24:00,Push Day,1h 5m,Bench Press,1,60,8,,,,,",
        "2024-03-11 18:24:00,Push Day,1h 5m,Bench Press,2,65,6,,,,,"
    ].joined(separator: "\n") + "\n"

    @Test("a detached parse followed by a main-actor preview matches the one-call preview")
    func detachedParseMatchesOneCallPreview() async throws {
        let store = try makeStore()
        let csv = Self.csv
        let parsed = await Task.detached(priority: .userInitiated) {
            WorkoutImport.parse(csv: csv, assumedWeightUnit: .lb)
        }.value
        let result = try #require(parsed)
        let split = WorkoutImportService.preview(result: result, store: store, assumedWeightUnit: .lb)
        let direct = try #require(
            WorkoutImportService.preview(csv: csv, store: store, assumedWeightUnit: .lb)
        )

        #expect(split.source == direct.source)
        #expect(split.workouts == direct.workouts)
        #expect(split.setsCount == direct.setsCount)
        #expect(split.unmatchedExerciseNames == direct.unmatchedExerciseNames)
        #expect(split.weightUnit == direct.weightUnit)
        #expect(split.weightUnit == .lb)
    }
}
