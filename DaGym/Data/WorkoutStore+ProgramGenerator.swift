import Foundation
import GymCore
import SwiftData

/// What `applyProgramDraft` created, so one Undo can delete exactly that and nothing else.
struct GeneratedProgramApplication: Hashable {
    var programID: UUID
    var routineIDs: [UUID]
    var name: String
}

/// The program generator's store side (plan.md §6.6): the candidate pool the picker chooses
/// from, and turning a validated `ProgramDraft` into routines plus a `ProgramModel` through the
/// same `saveRoutine`/`ProgramModel` paths the routine builder and `createProgram(from:)` use.
extension WorkoutStore {
    /// The lifter's equipment as the questionnaire's default — the active profile, or every
    /// kind the library uses when no profile is set up.
    func equipmentKindsForProgram() -> Set<String> {
        if let profile = activeProfile(), !profile.availableEquipment.isEmpty {
            return Set(profile.availableEquipment)
        }
        return Set(substitutionCandidates().map(\.equipment))
    }

    func programPool(for template: ProgramTemplate, request: ProgramRequest) -> [SubstitutionCandidate] {
        ProgramExercisePool.candidates(for: template, library: substitutionCandidates(), request: request)
    }

    /// Creates one routine per template day and a program cycling them, with the template's
    /// progression rule and one deload week closing the cycle. Not started: the lifter starts it
    /// from Programmes, the same as a starter program. Returns nil (and inserts nothing) if any
    /// pick no longer resolves to a library exercise.
    @discardableResult
    func applyProgramDraft(
        _ draft: ProgramDraft, template: ProgramTemplate, request: ProgramRequest
    ) -> GeneratedProgramApplication? {
        let pool = programPool(for: template, request: request)
        guard let validated = try? ProgramDraftValidator.validate(
            draft, template: template, pool: pool, request: request
        ) else { return nil }
        let (low, high) = Self.headlineRepRange(template)
        var routineIDs: [UUID] = []
        for day in template.days {
            let drafts = day.slots.compactMap { slot -> RoutineExerciseDraft? in
                guard let exerciseID = validated.exerciseID(for: slot.id) else { return nil }
                let sets = (0..<slot.sets).map { _ in
                    PlannedSetDraft(kind: .working, targetReps: slot.repLow, targetRepsHigh: slot.repHigh)
                }
                return RoutineExerciseDraft(exerciseID: exerciseID, sets: sets)
            }
            guard drafts.count == day.slots.count else {
                routineIDs.forEach(deleteRoutine)
                return nil
            }
            let name = "\(day.name) · \(validated.name)"
            let routine = saveRoutine(
                id: nil, name: name, progressionRule: Self.ruleKey(template.rule),
                repRangeLow: low, repRangeHigh: high, rule: template.rule, exercises: drafts
            )
            routineIDs.append(routine.id)
        }
        let model = ProgramModel(name: validated.name, weeks: template.weeks)
        model.routineIDs = routineIDs
        context.insert(model)
        model.programWeeks = (1...template.weeks).map { index in
            let kind: ProgramWeekKind = ProgramTemplateEngine.weekIsDeload(index, weeks: template.weeks)
                ? .deload : .normal
            let week = ProgramWeekModel(index: index, kind: kind.rawValue, program: model)
            context.insert(week)
            return week
        }
        save()
        return GeneratedProgramApplication(programID: model.id, routineIDs: routineIDs, name: validated.name)
    }

    /// Deletes exactly what `applyProgramDraft` created. `deleteRoutine` already strips each id
    /// from any program and the schedule.
    func undoProgramApplication(_ application: GeneratedProgramApplication) {
        let programID = application.programID
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == programID })
        descriptor.fetchLimit = 1
        if let model = fetchFirst(descriptor) { context.delete(model) }
        application.routineIDs.forEach(deleteRoutine)
        save()
    }

    /// The compound slots' range, for the routine's legacy display fields.
    private static func headlineRepRange(_ template: ProgramTemplate) -> (Int, Int) {
        let slot = template.slots.first { $0.mechanic == "compound" } ?? template.slots.first
        return (slot?.repLow ?? 6, slot?.repHigh ?? 8)
    }

    private static func ruleKey(_ rule: ProgressionRule) -> String {
        switch rule {
        case .linear: "linear"
        case .doubleProgression: "doubleProgression"
        case .linearAMRAP: "linearAMRAP"
        case .rpeBased: "rpeBased"
        case .percentOfTrainingMax: "percentOfTrainingMax"
        case .bodyweight: "bodyweight"
        case .assisted: "assisted"
        case .timed: "timed"
        }
    }
}
