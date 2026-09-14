import Foundation

/// Parses a FitNotes CSV export. One row per set; unlike Strong/Hevy there's no workout-name
/// column, so every row on the same `Date` becomes one workout. `Weight (kgs)`/`Weight (lbs)` in
/// the header says which unit the weight column is in — a bare `Weight` header falls back to a
/// per-row `Weight Unit` column when present, then to the unit the user picked in the preview;
/// `Distance Unit` (mi/km) says what `Distance` is in. FitNotes 2 (iOS) adds a `Kind` column
/// (warm-ups) and writes `Notes` instead of `Comment`.
enum FitNotesCSVImporter {
    static func parse(rows: [[String]], assumedUnit: WeightUnit? = nil) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .fitNotes, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight (kgs)"
        let units = UnitColumns(
            weightColumn: weightColumn, weightColumnUnit: ImportRow.columnUnit(named: weightColumn),
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
                let wasEmpty = try appendRow(row, columns: columns, units: units, into: &builder)
                if wasEmpty { emptyRows += 1 }
            } catch let error as ImportRowError {
                problems.append(ImportProblem(line: line, message: error.message))
            } catch {
                problems.append(ImportProblem(line: line, message: "Couldn't read this row."))
            }
        }
        return ImportResult(
            source: .fitNotes, workouts: builder.finish(), problems: problems, emptyRows: emptyRows,
            weightUnitAssumed: units.weightColumnUnit == nil && !sawPerRowUnit
        )
    }

    private struct UnitColumns {
        var weightColumn: String
        var weightColumnUnit: WeightUnit?
        var assumedUnit: WeightUnit?
    }

    /// Returns `true` when the row had nothing measured and was skipped instead of appended.
    private static func appendRow(
        _ row: [String], columns: ColumnMap, units: UnitColumns, into builder: inout WorkoutBuilder
    ) throws -> Bool {
        guard let dateText = columns.value(row, "Date"),
              let startedAt = ImportDateFormat.fitNotes(dateText) else {
            throw ImportRowError("Missing or unreadable date.")
        }
        guard let exerciseName = columns.value(row, "Exercise") else {
            throw ImportRowError("Missing exercise.")
        }
        let weight = try ImportRow.weightKg(
            columns.value(row, units.weightColumn), columnUnit: units.weightColumnUnit,
            perRowUnit: columns.value(row, "Weight Unit") ?? columns.value(row, "unit"),
            assumedUnit: units.assumedUnit
        )
        let repsText = columns.value(row, "Reps")
        let reps = try repsText.map { try ImportRow.reps($0) }
        let distanceUnit = columns.value(row, "Distance Unit") ?? "km"
        let distance = try ImportRow.distance(columns.value(row, "Distance"), unit: distanceUnit)
        let durationSeconds = try ImportRow.clockDuration(columns.value(row, "Time"))
        guard weight != 0 || (reps ?? 0) != 0 || durationSeconds != nil || distance != nil else {
            return true
        }
        let set = ImportedSet(
            kind: setKind(columns.value(row, "Kind")), weightKg: weight, reps: reps ?? 0,
            durationSeconds: durationSeconds, distanceMeters: distance
        )
        let note = columns.value(row, "Comment") ?? columns.value(row, "Notes")
        let entry = WorkoutRowInfo(
            startedAt: startedAt, endedAt: nil, title: "Workout", workoutNotes: "",
            exerciseName: exerciseName, exerciseNote: ImportParsing.text(note),
            exerciseCategory: columns.value(row, "Category")
        )
        builder.addSet(set, workoutKey: dateText, entry: entry)
        return false
    }

    /// FitNotes 2 (iOS) writes a `Kind` column; anything mentioning "warm" is a warm-up, since
    /// there's no other set-kind vocabulary in FitNotes exports.
    private static func setKind(_ raw: String?) -> SetKind {
        guard let raw, raw.lowercased().contains("warm") else { return .working }
        return .warmup
    }
}
