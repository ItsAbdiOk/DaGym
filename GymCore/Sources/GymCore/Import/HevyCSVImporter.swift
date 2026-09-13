import Foundation

/// Parses a Hevy CSV export. One row per set; `weight_kg`/`weight_lbs` in the header says which
/// unit the weight column is in. `set_type` is `normal`/`warmup`/`dropset`/`failure`.
enum HevyCSVImporter {
    static func parse(rows: [[String]]) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .hevy, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight_kg"
        let weightUnit: WeightUnit = weightColumn.contains("lb") ? .lb : .kg

        var builder = WorkoutBuilder()
        var problems: [ImportProblem] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard !row.isEmpty, row.contains(where: { !$0.isEmpty }) else { continue }
            do {
                try appendRow(
                    row, columns: columns, weightColumn: weightColumn, weightUnit: weightUnit, into: &builder
                )
            } catch let error as ImportRowError {
                problems.append(ImportProblem(line: line, message: error.message))
            } catch {
                problems.append(ImportProblem(line: line, message: "Couldn't read this row."))
            }
        }
        return ImportResult(source: .hevy, workouts: builder.finish(), problems: problems)
    }

    private static func appendRow(
        _ row: [String], columns: ColumnMap, weightColumn: String, weightUnit: WeightUnit,
        into builder: inout WorkoutBuilder
    ) throws {
        guard let startText = columns.value(row, "start_time"),
              let startedAt = ImportDateFormat.hevy(startText) else {
            throw ImportRowError("Missing or unreadable start_time.")
        }
        guard let exerciseName = columns.value(row, "exercise_title") else {
            throw ImportRowError("Missing exercise_title.")
        }
        let weight = try weightKg(row, columns: columns, weightColumn: weightColumn, unit: weightUnit)
        guard let repsText = columns.value(row, "reps") else {
            throw ImportRowError("Missing reps.")
        }
        guard let reps = ImportParsing.int(repsText) else {
            throw ImportRowError("Unreadable reps value \"\(repsText)\".")
        }
        let title = columns.value(row, "title") ?? "Workout"
        let endedAt = columns.value(row, "end_time").flatMap(ImportDateFormat.hevy)
        let distance = ImportParsing.metersFromDistance(
            ImportParsing.double(columns.value(row, "distance_km")), unit: "km"
        )
        let set = ImportedSet(
            kind: setKind(columns.value(row, "set_type")), weightKg: weight, reps: reps,
            durationSeconds: ImportParsing.int(columns.value(row, "duration_seconds")),
            distanceMeters: distance, rpe: ImportParsing.double(columns.value(row, "rpe"))
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt, endedAt: endedAt, title: title,
            workoutNotes: columns.value(row, "description") ?? "", exerciseName: exerciseName,
            exerciseNote: columns.value(row, "exercise_notes") ?? ""
        )
        builder.addSet(set, workoutKey: "\(startText)|\(title)", entry: entry)
    }

    private static func weightKg(
        _ row: [String], columns: ColumnMap, weightColumn: String, unit: WeightUnit
    ) throws -> Double {
        guard let text = columns.value(row, weightColumn) else { return 0 }
        guard let value = ImportParsing.double(text) else {
            throw ImportRowError("Unreadable weight value \"\(text)\".")
        }
        return unit == .kg ? value : WeightUnit.lb.toKg(value)
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
