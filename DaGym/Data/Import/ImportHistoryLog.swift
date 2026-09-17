import Foundation
import GymCore
import os

/// One finished import — when, from where, and what landed — as Settings › Data & backup ›
/// Import history lists it.
struct ImportHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    /// One "12 workouts" line of the entry.
    struct Count: Codable, Hashable, Sendable {
        var label: String
        var value: Int

        var text: String { "\(value) \(label)\(value == 1 ? "" : "s")" }
    }

    var id = UUID()
    var date: Date
    /// "Backup", "Strong", "Hevy", "FitNotes" or "Apple Health".
    var source: String
    /// Only the non-zero counts, in the order the import reports them.
    var counts: [Count]
    var problems = 0

    /// "12 workouts, 3 routines · 1 problem", or "Nothing new" for an import that changed
    /// nothing (a file restored twice).
    var summary: String {
        var text = counts.isEmpty ? "Nothing new" : counts.map(\.text).joined(separator: ", ")
        if problems > 0 { text += " · \(problems) problem\(problems == 1 ? "" : "s")" }
        return text
    }

    // MARK: - From each import path's report

    static func backup(_ report: ImportReport, date: Date = Date()) -> ImportHistoryEntry {
        ImportHistoryEntry(
            date: date, source: "Backup",
            counts: nonZero([
                ("workout", report.workoutsImported), ("routine", report.routinesImported),
                ("custom exercise", report.exercisesImported),
                ("bodyweight reading", report.bodyMeasurementsImported),
                ("equipment profile", report.equipmentProfilesImported), ("photo", report.photosImported),
                ("note", report.exerciseNotesImported), ("skipped workout", report.workoutsSkipped)
            ]),
            problems: report.problems.count
        )
    }

    static func workouts(
        _ report: WorkoutImportReport, source: ImportSource, date: Date = Date()
    ) -> ImportHistoryEntry {
        ImportHistoryEntry(
            date: date, source: source.displayName,
            counts: nonZero([
                ("workout", report.workoutsImported), ("set", report.setsImported),
                ("new exercise", report.exercisesCreated), ("skipped workout", report.workoutsSkipped)
            ]),
            problems: report.problems.count
        )
    }

    static func health(workouts: Int, date: Date = Date()) -> ImportHistoryEntry {
        ImportHistoryEntry(date: date, source: "Apple Health", counts: nonZero([("workout", workouts)]))
    }

    private static func nonZero(_ pairs: [(String, Int)]) -> [Count] {
        pairs.filter { $0.1 > 0 }.map { Count(label: $0.0, value: $0.1) }
    }
}

/// The persisted list behind Import history: a small JSON file in Application Support, newest
/// first, capped at `capacity`. Deliberately not a SwiftData model — the main store mirrors to
/// CloudKit and this is a device-local record of what was pulled *onto this device*. Every
/// import path (`BackupService.import`, `WorkoutImportService.apply`,
/// `HealthInsightsService.importPendingExternalWorkouts`) takes the log as a parameter that
/// defaults to `shared`, so a test can hand in `scratch()` instead.
@MainActor
final class ImportHistoryLog {
    /// The app's log: `Application Support/import-history.json`.
    static let shared = ImportHistoryLog(fileURL: defaultURL)

    static let capacity = 200

    let fileURL: URL
    private var cached: [ImportHistoryEntry]?
    private static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "import")

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// A throwaway log in the temporary directory, for tests and previews.
    static func scratch() -> ImportHistoryLog {
        ImportHistoryLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("import-history-\(UUID().uuidString).json"))
    }

    private static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("import-history.json")
    }

    /// Every recorded import, newest first.
    func entries() -> [ImportHistoryEntry] {
        if let cached { return cached }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? Self.decoder.decode([ImportHistoryEntry].self, from: $0) } ?? []
        let sorted = loaded.sorted { $0.date > $1.date }
        cached = sorted
        return sorted
    }

    /// Prepends `entry` and writes the file. An import that changed nothing is still recorded:
    /// "I restored that file twice and the second time did nothing" is exactly what the list
    /// is for.
    func record(_ entry: ImportHistoryEntry) {
        var all = entries()
        all.insert(entry, at: 0)
        if all.count > Self.capacity { all.removeLast(all.count - Self.capacity) }
        cached = all
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(all).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Import history write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Empties the log (Reset everything).
    func clear() {
        cached = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
