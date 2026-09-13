import Foundation

/// Parses a Strong app CSV export. One row per set; `Weight (kg)`/`Weight (lbs)` in the header
/// says which unit the `Weight` column is in — a bare `Weight` header instead falls back to a
/// per-row `Weight Unit` column when present. `Set Order` carries "W1"/"W2" for warm-ups and
/// "Dropset"/"Failure" for those kinds; anything else is a working set.
enum StrongCSVImporter {
    static func parse(rows: [[String]]) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .strong, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight"
        let unitColumns = UnitColumns(
            weightColumn: weightColumn, weightColumnUnit: columnUnit(named: weightColumn),
            distanceUnitColumn: columns.columnName(containing: ["distance", "unit"])
        )

        var builder = WorkoutBuilder()
        var problems: [ImportProblem] = []
        var emptyRows = 0
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard !row.isEmpty, row.contains(where: { !$0.isEmpty }) else { continue }
            do {
                let wasEmpty = try appendRow(row, columns: columns, unitColumns: unitColumns, into: &builder)
                if wasEmpty { emptyRows += 1 }
            } catch let error as ImportRowError {
                problems.append(ImportProblem(line: line, message: error.message))
            } catch {
                problems.append(ImportProblem(line: line, message: "Couldn't read this row."))
            }
        }
        return ImportResult(
            source: .strong, workouts: builder.finish(), problems: problems, emptyRows: emptyRows
        )
    }

    /// The weight column's name/header-inferred unit and the distance-unit column's name, bundled
    /// so `appendRow` doesn't thread three separate parameters for them.
    private struct UnitColumns {
        var weightColumn: String
        var weightColumnUnit: WeightUnit?
        var distanceUnitColumn: String?
    }

    /// Returns `true` when the row had nothing measured and was skipped instead of appended.
    private static func appendRow(
        _ row: [String], columns: ColumnMap, unitColumns: UnitColumns, into builder: inout WorkoutBuilder
    ) throws -> Bool {
        guard let dateText = columns.value(row, "Date"),
              let startedAt = ImportDateFormat.strong(dateText) else {
            throw ImportRowError("Missing or unreadable date.")
        }
        guard let exerciseName = columns.value(row, "Exercise Name") else {
            throw ImportRowError("Missing exercise name.")
        }
        let weight = try weightKg(
            row, columns: columns, weightColumn: unitColumns.weightColumn,
            columnUnit: unitColumns.weightColumnUnit
        )
        let reps = try reps(row, columns: columns)
        let durationSeconds = ImportParsing.int(columns.value(row, "Seconds"))
        let distanceUnit = unitColumns.distanceUnitColumn.flatMap { columns.value(row, $0) } ?? "m"
        let distance = ImportParsing.metersFromDistance(
            ImportParsing.double(columns.value(row, "Distance")), unit: distanceUnit
        )
        guard weight != 0 || reps != 0 || durationSeconds != nil || distance != nil else { return true }
        let workoutName = columns.value(row, "Workout Name") ?? "Workout"
        let freeTextDuration = ImportParsing.durationSecondsFromFreeText(columns.value(row, "Duration"))
        let set = ImportedSet(
            kind: setKind(columns.value(row, "Set Order")), weightKg: weight, reps: reps,
            durationSeconds: durationSeconds, distanceMeters: distance,
            rpe: reps == 0 ? nil : ImportParsing.rpe(columns.value(row, "RPE"))
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt,
            endedAt: freeTextDuration.map { startedAt.addingTimeInterval(TimeInterval($0)) },
            title: workoutName, workoutNotes: columns.value(row, "Workout Notes") ?? "",
            exerciseName: exerciseName, exerciseNote: columns.value(row, "Notes") ?? ""
        )
        builder.addSet(set, workoutKey: "\(dateText)|\(workoutName)", entry: entry)
        return false
    }

    /// The unit named by the weight column's own header (e.g. "Weight (lbs)"), or `nil` when the
    /// header is ambiguous (bare "Weight") and a per-row unit column should decide instead.
    private static func columnUnit(named weightColumn: String) -> WeightUnit? {
        if weightColumn.contains("lb") { return .lb }
        if weightColumn.contains("kg") { return .kg }
        return nil
    }

    private static func weightKg(
        _ row: [String], columns: ColumnMap, weightColumn: String, columnUnit: WeightUnit?
    ) throws -> Double {
        guard let text = columns.value(row, weightColumn) else { return 0 }
        let perRowUnit = columns.value(row, "Weight Unit") ?? columns.value(row, "unit")
        guard let value = ImportParsing.weightKg(text, columnUnit: columnUnit, perRowUnit: perRowUnit) else {
            throw ImportRowError("Unreadable weight value \"\(text)\".")
        }
        return value
    }

    private static func reps(_ row: [String], columns: ColumnMap) throws -> Int {
        guard let text = columns.value(row, "Reps") else { return 0 }
        guard let value = ImportParsing.int(text) else {
            throw ImportRowError("Unreadable reps value \"\(text)\".")
        }
        return value
    }

    private static func setKind(_ raw: String?) -> SetKind {
        guard let raw else { return .working }
        let lower = raw.lowercased()
        if lower.hasPrefix("w"), lower.dropFirst().allSatisfy(\.isNumber) { return .warmup }
        if lower.contains("drop") { return .drop }
        if lower.contains("fail") { return .failure }
        return .working
    }
}

/// A row that couldn't be turned into a set; carries just the human-readable reason, the line
/// number is attached by the caller.
struct ImportRowError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
