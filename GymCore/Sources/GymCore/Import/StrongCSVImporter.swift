import Foundation

/// Parses a Strong app CSV export. One row per set; `Weight (kg)`/`Weight (lbs)` in the header
/// says which unit the `Weight` column is in — a bare `Weight` header instead falls back to a
/// per-row `Weight Unit` column when present, then to the unit the user picked in the preview.
/// `Set Order` carries "W1"/"W2" for warm-ups and "Dropset"/"Failure" for those kinds; anything
/// else is a working set.
///
/// Real exports write a literal `0` in `Distance` and `Seconds` on every ordinary weight set
/// rather than leaving them blank, so both are read through `ImportRow`, which treats a measured
/// zero as "not measured" — otherwise every bench press would be stored as a 0-second, 0-metre
/// set, and an all-zero row would slip past the nothing-measured guard as a 0 kg × 0 set.
///
/// The workout duration is `Duration` in older exports and `Workout Duration` in newer ones; both
/// are read, so a recent file doesn't fall back to the one-hour default for every session.
enum StrongCSVImporter {
    static func parse(rows: [[String]], assumedUnit: WeightUnit? = nil) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .strong, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight"
        let unitColumns = UnitColumns(
            weightColumn: weightColumn, weightColumnUnit: ImportRow.columnUnit(named: weightColumn),
            distanceUnitColumn: columns.columnName(containing: ["distance", "unit"]),
            assumedUnit: assumedUnit
        )

        var builder = WorkoutBuilder()
        var problems: [ImportProblem] = []
        var emptyRows = 0
        var sawPerRowUnit = false
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard !row.isEmpty, row.contains(where: { !$0.isEmpty }) else { continue }
            if ImportParsing.weightUnit(from: columns.value(row, "Weight Unit")) != nil {
                sawPerRowUnit = true
            }
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
            source: .strong, workouts: builder.finish(), problems: problems, emptyRows: emptyRows,
            weightUnitAssumed: unitColumns.weightColumnUnit == nil && !sawPerRowUnit
        )
    }

    /// The weight column's name/header-inferred unit and the distance-unit column's name, bundled
    /// so `appendRow` doesn't thread four separate parameters for them.
    private struct UnitColumns {
        var weightColumn: String
        var weightColumnUnit: WeightUnit?
        var distanceUnitColumn: String?
        var assumedUnit: WeightUnit?
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
        let weight = try ImportRow.weightKg(
            columns.value(row, unitColumns.weightColumn), columnUnit: unitColumns.weightColumnUnit,
            perRowUnit: columns.value(row, "Weight Unit") ?? columns.value(row, "unit"),
            assumedUnit: unitColumns.assumedUnit
        )
        let reps = try ImportRow.reps(columns.value(row, "Reps"))
        let durationSeconds = try ImportRow.seconds(columns.value(row, "Seconds"))
        let distanceUnit = unitColumns.distanceUnitColumn.flatMap { columns.value(row, $0) } ?? "m"
        let distance = try ImportRow.distance(columns.value(row, "Distance"), unit: distanceUnit)
        guard weight != 0 || reps != 0 || durationSeconds != nil || distance != nil else { return true }
        let workoutName = columns.value(row, "Workout Name") ?? "Workout"
        let set = ImportedSet(
            kind: setKind(columns.value(row, "Set Order")), weightKg: weight, reps: reps,
            durationSeconds: durationSeconds, distanceMeters: distance,
            rpe: reps == 0 ? nil : ImportParsing.rpe(columns.value(row, "RPE"))
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt, endedAt: endedAt(from: startedAt, row: row, columns: columns),
            title: workoutName, workoutNotes: ImportParsing.text(columns.value(row, "Workout Notes")),
            exerciseName: exerciseName, exerciseNote: ImportParsing.text(columns.value(row, "Notes"))
        )
        builder.addSet(set, workoutKey: "\(dateText)|\(workoutName)", entry: entry)
        return false
    }

    /// Strong writes the session length as free text ("1h 5m") under `Duration`; newer exports
    /// name that column `Workout Duration` instead, so both are consulted.
    private static func endedAt(from startedAt: Date, row: [String], columns: ColumnMap) -> Date? {
        let text = columns.value(row, "Duration") ?? columns.value(row, "Workout Duration")
        guard let seconds = ImportParsing.durationSecondsFromFreeText(text) else { return nil }
        return startedAt.addingTimeInterval(TimeInterval(seconds))
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
