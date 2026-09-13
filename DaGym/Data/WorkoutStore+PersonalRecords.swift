import Foundation
import GymCore
import SwiftData

/// One earned record, formatted for display — see `GymCore.PersonalRecords.formatLine`.
struct PersonalRecordLine: Identifiable, Hashable {
    var id = UUID()
    var kindLabel: String
    var line: String
    var date: Date
}

/// Every cached record for one exercise, for `PersonalRecordsView`.
struct ExerciseRecords: Identifiable {
    var id: UUID
    var exerciseName: String
    var records: [PersonalRecordLine]
}

extension WorkoutStore {
    /// All cached `PersonalRecordModel`s, grouped by exercise and sorted alphabetically.
    /// Records within an exercise are newest first. Only e1RM is cached today (see
    /// `WorkoutStore+History.swift`'s `evaluatePRs`), so most exercises show one record.
    func personalRecords() -> [ExerciseRecords] {
        let models = (try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? []
        let grouped = Dictionary(grouping: models) { $0.exerciseID }
        return grouped
            .compactMap { exerciseID, models -> ExerciseRecords? in
                guard let exerciseID, let exerciseModel = fetchExerciseModel(id: exerciseID) else {
                    return nil
                }
                let order = PRKind.allCases
                let lines = models
                    .sorted { lhs, rhs in
                        let li = order.firstIndex(of: PRKind(rawValue: lhs.kind) ?? .e1rm) ?? 0
                        let ri = order.firstIndex(of: PRKind(rawValue: rhs.kind) ?? .e1rm) ?? 0
                        return li != ri ? li < ri : lhs.date > rhs.date
                    }
                    .map(personalRecordLine)
                return ExerciseRecords(id: exerciseID, exerciseName: exerciseModel.name, records: lines)
            }
            .sorted { $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending }
    }

    private func personalRecordLine(_ model: PersonalRecordModel) -> PersonalRecordLine {
        let kind = PRKind(rawValue: model.kind) ?? .e1rm
        let record = PersonalRecord(
            kind: kind, value: model.value, weightKg: model.weightKg, reps: model.reps, date: model.date
        )
        return PersonalRecordLine(
            kindLabel: Self.kindLabel(kind), line: PersonalRecords.formatLine(record), date: model.date
        )
    }

    private static func kindLabel(_ kind: PRKind) -> String {
        switch kind {
        case .e1rm: "Estimated 1RM"
        case .maxWeight: "Heaviest weight"
        case .maxRepsAtWeight: "Most reps"
        case .volume: "Volume"
        case .longestHold: "Longest hold"
        case .leastAssistance: "Least assistance"
        }
    }
}
