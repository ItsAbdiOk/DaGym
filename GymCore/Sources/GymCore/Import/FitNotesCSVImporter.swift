import Foundation

/// Parses a FitNotes CSV export. One row per set; unlike Strong/Hevy there's no workout-name or
/// set-kind column, so every row on the same `Date` becomes one workout and every set is
/// `.working`. `Weight (kgs)`/`Weight (lbs)` in the header says which unit the weight column is
/// in; `Distance Unit` (mi/km) says what `Distance` is in.
enum FitNotesCSVImporter {
    static func parse(rows: [[String]]) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .fitNotes, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight (kgs)"
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
        return ImportResult(source: .fitNotes, workouts: builder.finish(), problems: problems)
    }

    private static func appendRow(
        _ row: [String], columns: ColumnMap, weightColumn: String, weightUnit: WeightUnit,
        into builder: inout WorkoutBuilder
    ) throws {
        guard let dateText = columns.value(row, "Date"),
              let startedAt = ImportDateFormat.fitNotes(dateText) else {
            throw ImportRowError("Missing or unreadable date.")
        }
        guard let exerciseName = columns.value(row, "Exercise") else {
            throw ImportRowError("Missing exercise.")
        }
        let weight = try weightKg(row, columns: columns, weightColumn: weightColumn, unit: weightUnit)
        guard let repsText = columns.value(row, "Reps") else {
            throw ImportRowError("Missing reps.")
        }
        guard let reps = ImportParsing.int(repsText) else {
            throw ImportRowError("Unreadable reps value \"\(repsText)\".")
        }
        let distanceUnit = columns.value(row, "Distance Unit") ?? "km"
        let distance = ImportParsing.metersFromDistance(
            ImportParsing.double(columns.value(row, "Distance")), unit: distanceUnit
        )
        let set = ImportedSet(
            kind: .working, weightKg: weight, reps: reps,
            durationSeconds: ImportParsing.durationSecondsFromClock(columns.value(row, "Time")),
            distanceMeters: distance
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt, endedAt: nil, title: "Workout", workoutNotes: "",
            exerciseName: exerciseName, exerciseNote: columns.value(row, "Comment") ?? ""
        )
        builder.addSet(set, workoutKey: dateText, entry: entry)
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
}
