import Foundation

/// Parses a Hevy CSV export. One row per set; `weight_kg`/`weight_lbs` in the header says which
/// unit the weight column is in — a bare `weight` header falls back to a per-row `weight_unit`
/// column, then to the unit the user picked in the preview. `set_type` is
/// `normal`/`warmup`/`dropset`/`failure`. A row with blank `reps` but a
/// `duration_seconds`/`distance_km` is a timed or cardio set, not an error.
///
/// An imperial export pairs `weight_lbs` with `distance_miles` rather than `distance_km`, so the
/// distance column is found by name and its unit read off that name instead of being hard-coded
/// to km. `superset_id` is carried through as the exercise's superset group so supersets survive.
enum HevyCSVImporter {
    static func parse(rows: [[String]], assumedUnit: WeightUnit? = nil) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .hevy, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight_kg"
        let distanceColumn = columns.columnName(containing: ["distance"])
        let unitColumns = UnitColumns(
            weightColumn: weightColumn, weightColumnUnit: ImportRow.columnUnit(named: weightColumn),
            distanceColumn: distanceColumn,
            distanceUnit: distanceColumn.flatMap(ImportParsing.distanceUnit(fromColumnName:)) ?? "km",
            assumedUnit: assumedUnit
        )

        var builder = WorkoutBuilder()
        var problems: [ImportProblem] = []
        var emptyRows = 0
        var sawPerRowUnit = false
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard !row.isEmpty, row.contains(where: { !$0.isEmpty }) else { continue }
            if ImportParsing.weightUnit(from: columns.value(row, "weight_unit")) != nil {
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
            source: .hevy, workouts: builder.finish(), problems: problems, emptyRows: emptyRows,
            weightUnitAssumed: unitColumns.weightColumnUnit == nil && !sawPerRowUnit
        )
    }

    /// The weight/distance columns and the units their names imply, bundled so `appendRow`
    /// doesn't thread five separate parameters.
    private struct UnitColumns {
        var weightColumn: String
        var weightColumnUnit: WeightUnit?
        var distanceColumn: String?
        var distanceUnit: String
        var assumedUnit: WeightUnit?
    }

    /// Returns `true` when the row had nothing measured and was skipped instead of appended.
    private static func appendRow(
        _ row: [String], columns: ColumnMap, unitColumns: UnitColumns, into builder: inout WorkoutBuilder
    ) throws -> Bool {
        guard let startText = columns.value(row, "start_time"),
              let startedAt = ImportDateFormat.hevy(startText) else {
            throw ImportRowError("Missing or unreadable start_time.")
        }
        guard let exerciseName = columns.value(row, "exercise_title") else {
            throw ImportRowError("Missing exercise_title.")
        }
        let weight = try ImportRow.weightKg(
            columns.value(row, unitColumns.weightColumn), columnUnit: unitColumns.weightColumnUnit,
            perRowUnit: columns.value(row, "weight_unit") ?? columns.value(row, "unit"),
            assumedUnit: unitColumns.assumedUnit
        )
        let repsText = columns.value(row, "reps")
        let reps = try repsText.map { try ImportRow.reps($0) }
        let durationSeconds = try ImportRow.seconds(columns.value(row, "duration_seconds"))
        let distance = try ImportRow.distance(
            unitColumns.distanceColumn.flatMap { columns.value(row, $0) }, unit: unitColumns.distanceUnit
        )
        guard weight != 0 || (reps ?? 0) != 0 || durationSeconds != nil || distance != nil else {
            return true
        }
        let title = columns.value(row, "title") ?? "Workout"
        let effectiveReps = reps ?? 0
        let set = ImportedSet(
            kind: setKind(columns.value(row, "set_type")), weightKg: weight, reps: effectiveReps,
            durationSeconds: durationSeconds, distanceMeters: distance,
            rpe: effectiveReps == 0 ? nil : ImportParsing.rpe(columns.value(row, "rpe"))
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt, endedAt: columns.value(row, "end_time").flatMap(ImportDateFormat.hevy),
            title: title, workoutNotes: ImportParsing.text(columns.value(row, "description")),
            exerciseName: exerciseName,
            exerciseNote: ImportParsing.text(columns.value(row, "exercise_notes")),
            supersetGroup: ImportParsing.int(columns.value(row, "superset_id"))
        )
        builder.addSet(set, workoutKey: "\(startText)|\(title)", entry: entry)
        return false
    }

    private static func setKind(_ raw: String?) -> SetKind {
        switch raw?.lowercased() {
        case "warmup": .warmup
        case "dropset": .drop
        case "failure": .failure
        default: .working
        }
    }
}
