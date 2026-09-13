import Foundation

/// Parses a Strong app CSV export. One row per set; `Weight (kg)`/`Weight (lbs)` in the header
/// says which unit the `Weight` column is in. `Set Order` carries "W1"/"W2" for warm-ups and
/// "Dropset"/"Failure" for those kinds; anything else is a working set.
enum StrongCSVImporter {
    static func parse(rows: [[String]]) -> ImportResult {
        guard let header = rows.first else {
            return ImportResult(source: .strong, workouts: [], problems: [])
        }
        let columns = ColumnMap(header: header)
        let weightColumn = columns.columnName(containing: ["weight"]) ?? "weight"
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
        return ImportResult(source: .strong, workouts: builder.finish(), problems: problems)
    }

    private static func appendRow(
        _ row: [String], columns: ColumnMap, weightColumn: String, weightUnit: WeightUnit,
        into builder: inout WorkoutBuilder
    ) throws {
        guard let dateText = columns.value(row, "Date"),
              let startedAt = ImportDateFormat.strong(dateText) else {
            throw ImportRowError("Missing or unreadable date.")
        }
        guard let exerciseName = columns.value(row, "Exercise Name") else {
            throw ImportRowError("Missing exercise name.")
        }
        let weight = try weightKg(row, columns: columns, weightColumn: weightColumn, unit: weightUnit)
        let reps = try reps(row, columns: columns)
        let workoutName = columns.value(row, "Workout Name") ?? "Workout"
        let durationSeconds = ImportParsing.durationSecondsFromFreeText(columns.value(row, "Duration"))
        let set = ImportedSet(
            kind: setKind(columns.value(row, "Set Order")), weightKg: weight, reps: reps,
            durationSeconds: ImportParsing.int(columns.value(row, "Seconds")),
            distanceMeters: ImportParsing.double(columns.value(row, "Distance")),
            rpe: ImportParsing.double(columns.value(row, "RPE"))
        )
        let entry = WorkoutRowInfo(
            startedAt: startedAt,
            endedAt: durationSeconds.map { startedAt.addingTimeInterval(TimeInterval($0)) },
            title: workoutName, workoutNotes: columns.value(row, "Workout Notes") ?? "",
            exerciseName: exerciseName, exerciseNote: columns.value(row, "Notes") ?? ""
        )
        builder.addSet(set, workoutKey: "\(dateText)|\(workoutName)", entry: entry)
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
