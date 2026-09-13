import Foundation

/// Parses a FitNotes CSV export. One row per set; unlike Strong/Hevy there's no workout-name
/// column, so every row on the same `Date` becomes one workout. `Weight (kgs)`/`Weight (lbs)` in
/// the header says which unit the weight column is in — a bare `Weight` header falls back to a
/// per-row `Weight Unit` column when present; `Distance Unit` (mi/km) says what `Distance` is in.
/// FitNotes 2 (iOS) adds a `Kind` column (warm-ups) and writes `Notes` instead of `Comment`.
enum FitNotesCSVImporter {
    static func parse(rows: [[String]]) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .fitNotes, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight (kgs)"
        let weightColumnUnit = columnUnit(named: weightColumn)

        var builder = WorkoutBuilder()
        var problems: [ImportProblem] = []
        var emptyRows = 0
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard !row.isEmpty, row.contains(where: { !$0.isEmpty }) else { continue }
            do {
                let wasEmpty = try appendRow(
                    row, columns: columns, weightColumn: weightColumn, weightColumnUnit: weightColumnUnit,
                    into: &builder
                )
                if wasEmpty { emptyRows += 1 }
            } catch let error as ImportRowError {
                problems.append(ImportProblem(line: line, message: error.message))
            } catch {
                problems.append(ImportProblem(line: line, message: "Couldn't read this row."))
            }
        }
        return ImportResult(
            source: .fitNotes, workouts: builder.finish(), problems: problems, emptyRows: emptyRows
        )
    }

    /// Returns `true` when the row had nothing measured and was skipped instead of appended.
    private static func appendRow(
        _ row: [String], columns: ColumnMap, weightColumn: String, weightColumnUnit: WeightUnit?,
        into builder: inout WorkoutBuilder
    ) throws -> Bool {
        guard let dateText = columns.value(row, "Date"),
              let startedAt = ImportDateFormat.fitNotes(dateText) else {
            throw ImportRowError("Missing or unreadable date.")
        }
        guard let exerciseName = columns.value(row, "Exercise") else {
            throw ImportRowError("Missing exercise.")
        }
        let weight = try weightKg(
            row, columns: columns, weightColumn: weightColumn, columnUnit: weightColumnUnit
        )
        let repsText = columns.value(row, "Reps")
        let reps = try repsText.map { text -> Int in
            guard let value = ImportParsing.int(text) else {
                throw ImportRowError("Unreadable reps value \"\(text)\".")
            }
            return value
        }
        let distanceUnit = columns.value(row, "Distance Unit") ?? "km"
        let distance = ImportParsing.metersFromDistance(
            ImportParsing.double(columns.value(row, "Distance")), unit: distanceUnit
        )
        let durationSeconds = ImportParsing.durationSecondsFromClock(columns.value(row, "Time"))
        guard weight != 0 || (reps ?? 0) != 0 || durationSeconds != nil || distance != nil else {
            return true
        }
        let set = ImportedSet(
            kind: setKind(columns.value(row, "Kind")), weightKg: weight, reps: reps ?? 0,
            durationSeconds: durationSeconds, distanceMeters: distance
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt, endedAt: nil, title: "Workout", workoutNotes: "",
            exerciseName: exerciseName,
            exerciseNote: columns.value(row, "Comment") ?? columns.value(row, "Notes") ?? "",
            exerciseCategory: columns.value(row, "Category")
        )
        builder.addSet(set, workoutKey: dateText, entry: entry)
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

    /// FitNotes 2 (iOS) writes a `Kind` column; anything mentioning "warm" is a warm-up, since
    /// there's no other set-kind vocabulary in FitNotes exports.
    private static func setKind(_ raw: String?) -> SetKind {
        guard let raw, raw.lowercased().contains("warm") else { return .working }
        return .warmup
    }
}
