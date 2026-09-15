import Foundation
import GymCore

/// `CoachToolAnswering` over a `WorkoutStore`: the five question tools, each answered from an
/// existing store accessor and formatted in the lifter's unit. The text these return is what
/// the model may quote and what `CoachAnswerValidator` checks the answer's numbers against —
/// so every number the lifter could ask about is written out here, in full, exactly once.
@MainActor
final class CoachFactsSource: CoachToolAnswering {
    private let store: WorkoutStore
    private let unit: WeightUnit
    private let calendar: Calendar
    private let now: () -> Date

    init(
        store: WorkoutStore,
        unit: WeightUnit,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.unit = unit
        self.calendar = calendar
        self.now = now
    }

    var exerciseNamesForCoach: [String] { store.exercises().map(\.name) }

    func answerCoachQuery(_ query: CoachToolQuery) -> CoachToolResult {
        switch query {
        case .lastSessions(let exercise): lastSessions(exerciseName: exercise)
        case .weeklyVolume(let muscle, let weeks): weeklyVolume(muscleName: muscle, weeks: weeks)
        case .personalRecords(let exercise): personalRecords(exerciseName: exercise)
        case .adherence(let weeks): adherence(weeks: weeks)
        case .recovery(let muscle): recovery(muscleName: muscle)
        }
    }

    // MARK: - Tools

    private func lastSessions(exerciseName: String) -> CoachToolResult {
        guard let exercise = resolveExercise(exerciseName) else { return unknownExercise(exerciseName) }
        let history = store.exerciseHistory(exerciseID: exercise.id, limit: 3)
        guard !history.isEmpty else {
            return CoachToolResult(text: "No logged sessions of \(exercise.name) yet.")
        }
        let lines = history.map { entry in
            let sets = entry.workingSets.map { set in
                "\(unit.format(kg: set.weightKg)) \(unit.symbol) × \(set.reps)"
            }
            return "\(Self.dateFormatter.string(from: entry.date)): \(sets.joined(separator: ", "))"
        }
        let joinedLines = lines.joined(separator: "; ")
        return CoachToolResult(text: "Last \(history.count) sessions of \(exercise.name) — " + joinedLines)
    }

    private func weeklyVolume(muscleName: String, weeks: Int) -> CoachToolResult {
        guard let muscle = resolveMuscle(muscleName) else { return unknownMuscle(muscleName) }
        let clamped = min(max(weeks, 1), 12)
        let sets = store.bodySeries(
            weeks: clamped, calendar: calendar, balanceWindow: .days(clamped * 7), now: now()
        ).setsPerMuscle[muscle, default: 0]
        let perWeek = sets / Double(clamped)
        let text = "\(muscle.displayName): \(Self.oneDecimal(sets)) working sets over the last "
            + "\(clamped) weeks, about \(Self.oneDecimal(perWeek)) sets a week."
        return CoachToolResult(text: text)
    }

    private func personalRecords(exerciseName: String) -> CoachToolResult {
        guard let exercise = resolveExercise(exerciseName) else { return unknownExercise(exerciseName) }
        let recordsData = store.personalRecords(unit: unit)
        let records = recordsData.first { $0.id == exercise.id }?.records ?? []
        guard !records.isEmpty else {
            return CoachToolResult(text: "No personal records on \(exercise.name) yet.")
        }
        let lines = records.prefix(4).map { record in
            let dateStr = Self.dateFormatter.string(from: record.date)
            return "\(record.kindLabel): \(record.line) (\(dateStr))"
        }
        let joinedLines = lines.joined(separator: "; ")
        return CoachToolResult(text: "\(exercise.name) records — " + joinedLines)
    }

    private func adherence(weeks: Int) -> CoachToolResult {
        let clamped = min(max(weeks, 1), 12)
        let summary = AdherenceSummary.over(
            weeks: clamped, schedule: store.schedule(),
            loggedWorkoutDates: store.finishedWorkoutModelsNewestFirst().map(\.startedAt),
            now: now(), calendar: calendar
        )
        guard let percent = summary.percent else {
            return CoachToolResult(text: "No sessions were planned in the last \(clamped) weeks.")
        }
        let text = "Kept \(summary.kept) of \(summary.planned) planned sessions over the last "
            + "\(clamped) weeks, \(percent)% adherence."
        return CoachToolResult(text: text)
    }

    private func recovery(muscleName: String) -> CoachToolResult {
        guard let muscle = resolveMuscle(muscleName) else { return unknownMuscle(muscleName) }
        let snapshot = store.recoverySnapshot(now: now(), calendar: calendar)
        guard let reading = snapshot.perMuscle.first(where: { $0.muscle == muscle }) else {
            let msg = "\(muscle.displayName) hasn't been trained in the last two weeks: fully recovered."
            return CoachToolResult(text: msg)
        }
        let percent = Int(((1 - reading.spent) * 100).rounded())
        var text = "\(muscle.displayName) is \(percent)% recovered."
        if let recoveredBy = reading.recoveredBy {
            text += " Fresh again by \(Self.dateFormatter.string(from: recoveredBy))."
        }
        return CoachToolResult(text: text)
    }

    // MARK: - Helpers

    private func resolveExercise(_ name: String) -> ExerciseInfo? {
        let all = store.exercises()
        let lowered = name.lowercased()
        return all.first { $0.name.lowercased() == lowered }
            ?? CoachQuestionMatcher.exerciseMentioned(in: lowered, names: all.map(\.name)).flatMap { match in
                all.first { $0.name == match }
            }
    }

    private func resolveMuscle(_ name: String) -> Muscle? {
        let lowered = name.lowercased()
        return Muscle.allCases.first { $0.displayName.lowercased() == lowered || $0.rawValue == lowered }
            ?? CoachQuestionMatcher.muscleMentioned(in: lowered).flatMap { display in
                Muscle.allCases.first { $0.displayName == display }
            }
    }

    private func unknownExercise(_ name: String) -> CoachToolResult {
        CoachToolResult(text: "No exercise called \(name) in the library.")
    }

    private func unknownMuscle(_ name: String) -> CoachToolResult {
        CoachToolResult(text: "No muscle called \(name).")
    }

    private static func oneDecimal(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
