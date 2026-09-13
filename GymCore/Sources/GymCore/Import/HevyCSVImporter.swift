import Foundation

/// Parses a Hevy CSV export. One row per set; `weight_kg`/`weight_lbs` in the header says which
/// unit the weight column is in — a bare `weight` header falls back to a per-row `weight_unit`
/// column when present. `set_type` is `normal`/`warmup`/`dropset`/`failure`. A row with blank
/// `reps` but a `duration_seconds`/`distance_km` is a timed or cardio set, not an error.
enum HevyCSVImporter {
    static func parse(rows: [[String]]) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .hevy, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight_kg"
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
            source: .hevy, workouts: builder.finish(), problems: problems, emptyRows: emptyRows
        )
    }

    /// Returns `true` when the row had nothing measured and was skipped instead of appended.
    private static func appendRow(
        _ row: [String], columns: ColumnMap, weightColumn: String, weightColumnUnit: WeightUnit?,
        into builder: inout WorkoutBuilder
    ) throws -> Bool {
        guard let startText = columns.value(row, "start_time"),
              let startedAt = ImportDateFormat.hevy(startText) else {
            throw ImportRowError("Missing or unreadable start_time.")
        }
        guard let exerciseName = columns.value(row, "exercise_title") else {
            throw ImportRowError("Missing exercise_title.")
        }
        let weight = try weightKg(
            row, columns: columns, weightColumn: weightColumn, columnUnit: weightColumnUnit
        )
        let repsText = columns.value(row, "reps")
        let reps = try repsText.map { text -> Int in
            guard let value = ImportParsing.int(text) else {
                throw ImportRowError("Unreadable reps value \"\(text)\".")
            }
            return value
        }
        let durationSeconds = ImportParsing.int(columns.value(row, "duration_seconds"))
        let distance = ImportParsing.metersFromDistance(
            ImportParsing.double(columns.value(row, "distance_km")), unit: "km"
        )
        guard weight != 0 || (reps ?? 0) != 0 || durationSeconds != nil || distance != nil else {
            return true
        }
        let title = columns.value(row, "title") ?? "Workout"
        let endedAt = columns.value(row, "end_time").flatMap(ImportDateFormat.hevy)
        let effectiveReps = reps ?? 0
        let set = ImportedSet(
            kind: setKind(columns.value(row, "set_type")), weightKg: weight, reps: effectiveReps,
            durationSeconds: durationSeconds, distanceMeters: distance,
            rpe: effectiveReps == 0 ? nil : ImportParsing.rpe(columns.value(row, "rpe"))
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt, endedAt: endedAt, title: title,
            workoutNotes: columns.value(row, "description") ?? "", exerciseName: exerciseName,
            exerciseNote: columns.value(row, "exercise_notes") ?? ""
        )
        builder.addSet(set, workoutKey: "\(startText)|\(title)", entry: entry)
        return false
    }

    /// The unit named by the weight column's own header (e.g. "weight_lbs"), or `nil` when the
    /// header is ambiguous (bare "weight") and a per-row unit column should decide instead.
    private static func columnUnit(named weightColumn: String) -> WeightUnit? {
        if weightColumn.contains("lb") { return .lb }
        if weightColumn.contains("kg") { return .kg }
        return nil
    }

    private static func weightKg(
        _ row: [String], columns: ColumnMap, weightColumn: String, columnUnit: WeightUnit?
    ) throws -> Double {
        guard let text = columns.value(row, weightColumn) else { return 0 }
        let perRowUnit = columns.value(row, "weight_unit") ?? columns.value(row, "unit")
        guard let value = ImportParsing.weightKg(text, columnUnit: columnUnit, perRowUnit: perRowUnit) else {
            throw ImportRowError("Unreadable weight value \"\(text)\".")
        }
        return value
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
