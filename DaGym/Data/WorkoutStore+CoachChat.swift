import Foundation
import GymCore
import SwiftData

/// What applying a `CoachChatDraft` did, so the Undo toast can put it back exactly. Each case
/// carries the undo token its store path already returns — nothing new to reverse.
enum CoachChatApplication {
    case routine(id: UUID, name: String)
    case program(GeneratedProgramApplication)
    case schedule(ReviewApplication)
    case deload(ReviewApplication)
    case swap(ReviewApplication)

    /// What the lifter is told happened, for the toast.
    var message: String {
        switch self {
        case .routine(_, let name): "Saved \(name)"
        case .program(let application): "Created \(application.name)"
        case .schedule(let change), .deload(let change), .swap(let change): change.message
        }
    }
}

/// Why a draft could not be applied — the routine or exercise it targets is gone, or the
/// draft was never validated. The card shows `localizedDescription`.
enum CoachChatApplyError: LocalizedError, Equatable {
    case routineMissing
    case exerciseMissing(String)
    case notValidated
    case programEmpty

    var errorDescription: String? {
        switch self {
        case .routineMissing: "That routine no longer exists."
        case .exerciseMissing(let name): "\(name) is no longer in your library."
        case .notValidated: "This proposal was not checked against your library."
        case .programEmpty: "Your library has no exercise for one of the program's slots."
        }
    }
}

extension WorkoutStore {
    // MARK: - Profile facts

    /// The facts the system prompt states up front. `unit`, `weeklyGoal` and `goal` come from
    /// `Preferences` (the store never reads preferences itself); everything else from the store.
    func lifterProfileFacts(
        unit: WeightUnit, weeklyGoal: Int?, trainingGoal goal: TrainingGoal?, now: Date = Date(),
        calendar: Calendar = .current
    ) -> LifterProfileFacts {
        let profile = activeProfile()
        let availability = profile?.availability
        let since = calendar.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        let recent = workoutDates().filter { $0 >= since && $0 <= now }.count
        return LifterProfileFacts(
            unit: unit, weeklyGoal: weeklyGoal, bodyweightKg: latestBodyMeasurement()?.bodyweightKg,
            goal: goal, experience: nil, equipmentProfileName: profile?.name,
            equipmentTypes: profile.map { $0.availableEquipment.sorted() } ?? [],
            machines: availability.flatMap {
                $0.restrictsMachines ? $0.offeredMachines.map(\.displayName).sorted() : nil
            } ?? [],
            restrictsMachines: availability?.restrictsMachines ?? false,
            activeProgramName: activeProgramModel(now: now, calendar: calendar)?.name,
            routineNames: routines().map(\.name), workoutsLast4Weeks: recent,
            libraryByMuscle: coachLibraryByMuscle(availability: equipmentAvailabilityForProgram())
        )
    }

    /// Up to `perMuscle` allowed exercise names per primary muscle: what the lifter has trained
    /// first, then favourites, then the shortest names — the library's classics tend to be the
    /// short ones ("Bench Press" before "Incline Cable Chest Press, Single Arm").
    func coachLibraryByMuscle(
        availability: EquipmentAvailability, perMuscle: Int = 12
    ) -> [String: [String]] {
        let catalogue = exerciseCatalogue()
        var byMuscle: [String: [(name: String, rank: (Int, Int, Int))]] = [:]
        for exercise in exercises(in: catalogue) {
            guard availability.verdict(equipment: exercise.equipment, machine: exercise.machine) == .allowed,
                  let primary = exercise.primary.first else { continue }
            let trained = catalogue.bestByExercise[exercise.id] != nil ? 0 : 1
            let favourite = exercise.isFavorite ? 0 : 1
            byMuscle[primary.rawValue, default: []]
                .append((exercise.name, (trained, favourite, exercise.name.count)))
        }
        return byMuscle.mapValues { entries in
            entries.sorted { $0.rank < $1.rank }.prefix(perMuscle).map(\.name)
        }
    }

    /// The same, read straight from `Preferences` — what the chat screen calls.
    func lifterProfileFacts(
        preferences: Preferences, now: Date = Date()
    ) -> LifterProfileFacts {
        lifterProfileFacts(
            unit: preferences.weightUnit, weeklyGoal: preferences.weeklyGoal,
            trainingGoal: preferences.trainingGoal.coachGoal, now: now, calendar: preferences.trainingCalendar
        )
    }

    // MARK: - Apply / undo

    /// Saves a validated draft through the same paths the routine builder, the program
    /// generator, the schedule screen and the review cards use. Throws when the draft's target
    /// routine or exercise has gone since it was proposed.
    func apply(_ draft: CoachChatDraft) throws -> CoachChatApplication {
        switch draft {
        case .routine(let proposal):
            let routine = try saveRoutine(from: proposal)
            return .routine(id: routine.id, name: routine.name)
        case .program(let proposal):
            return .program(try applyProgram(proposal))
        case .schedule(let proposal):
            return .schedule(try applySchedule(proposal))
        case .deload(let proposal):
            return .deload(try applyDeload(proposal))
        case .swap(let proposal):
            return .swap(try applySwap(proposal))
        }
    }

    /// Puts back exactly what `apply` changed.
    func undo(_ application: CoachChatApplication) {
        switch application {
        case .routine(let id, _): deleteRoutine(id: id)
        case .program(let generated): undoProgramApplication(generated)
        case .schedule(let change), .deload(let change), .swap(let change): undoReviewChange(change)
        }
    }

    // MARK: - Routine

    private func saveRoutine(from proposal: RoutineProposal) throws -> RoutineInfo {
        let drafts = try proposal.exercises.map(Self.exerciseDraft)
        let reps = proposal.exercises.flatMap(\.sets).filter { $0.kind.countsTowardStats }.map(\.targetReps)
        let low = reps.min() ?? 6
        let high = reps.max() ?? max(8, low)
        let rule = proposal.rule.map { $0.progressionRule() }
        return saveRoutine(
            id: nil, name: proposal.name, notes: proposal.notes ?? "",
            progressionRule: rule.map(Self.ruleKey) ?? "doubleProgression",
            repRangeLow: low, repRangeHigh: high, rule: rule, exercises: drafts
        )
    }

    private static func exerciseDraft(_ spec: CoachChatExerciseSpec) throws -> RoutineExerciseDraft {
        guard let exerciseID = spec.exerciseID else { throw CoachChatApplyError.notValidated }
        return RoutineExerciseDraft(
            exerciseID: exerciseID, supersetGroup: spec.supersetGroup, restOverrideSeconds: spec.restSeconds,
            sets: spec.sets.map { set in
                PlannedSetDraft(
                    kind: set.kind, targetReps: set.targetReps, targetWeightKg: set.targetWeightKg,
                    targetRPE: set.rpe
                )
            }
        )
    }

    // MARK: - Program

    /// A template program goes through the generator's own picker and `applyProgramDraft`; one
    /// with routines spelled out saves each routine and wraps them in a `ProgramModel` the way
    /// `applyProgramDraft` does (one deload week closing the cycle).
    private func applyProgram(_ proposal: ProgramProposal) throws -> GeneratedProgramApplication {
        if proposal.usesTemplate {
            let request = ProgramRequest(
                goal: proposal.goal, daysPerWeek: proposal.daysPerWeek,
                sessionMinutes: proposal.sessionMinutes ?? 60,
                experience: proposal.experience ?? .intermediate,
                availableEquipment: equipmentKindsForProgram(),
                equipmentAvailability: equipmentAvailabilityForProgram()
            )
            let template = ProgramTemplateEngine.template(for: request)
            let pool = programPool(for: template, request: request)
            guard var draft = ProgramDefaultPicks.draft(template: template, pool: pool, request: request)
            else { throw CoachChatApplyError.programEmpty }
            draft.name = proposal.name
            guard let application = applyProgramDraft(draft, template: template, request: request) else {
                throw CoachChatApplyError.programEmpty
            }
            return application
        }
        var routineIDs: [UUID] = []
        do {
            for routine in proposal.routines {
                routineIDs.append(try saveRoutine(from: routine).id)
            }
        } catch {
            routineIDs.forEach(deleteRoutine)
            throw error
        }
        let weeks = ProgramTemplateEngine.weeks
        let model = ProgramModel(name: proposal.name, weeks: weeks)
        model.routineIDs = routineIDs
        context.insert(model)
        model.programWeeks = (1...weeks).map { index in
            let isDeload = ProgramTemplateEngine.weekIsDeload(index, weeks: weeks)
            let kind: ProgramWeekKind = isDeload ? .deload : .normal
            let week = ProgramWeekModel(index: index, kind: kind.rawValue, program: model)
            context.insert(week)
            return week
        }
        save()
        return GeneratedProgramApplication(programID: model.id, routineIDs: routineIDs, name: proposal.name)
    }

    // MARK: - Schedule

    /// Replaces the weekday plan with the proposal's days (date overrides are kept). Every
    /// routine id is checked again: one may have been deleted since the card was drawn.
    private func applySchedule(_ proposal: ScheduleProposal) throws -> ReviewApplication {
        let live = Set(routines().map(\.id))
        guard proposal.days.values.allSatisfy(live.contains) else { throw CoachChatApplyError.routineMissing }
        let previous = schedule()
        var updated = previous
        updated.dayRoutines = proposal.days.mapValues { [$0] }
        saveSchedule(updated)
        return ReviewApplication(previousSchedule: previous, message: "Schedule updated")
    }

    // MARK: - Deload

    /// Cuts the exercise's current working weight by the proposal's percent through
    /// `applyCoachDeload`, which rounds onto the lifter's own plate/stack grid.
    private func applyDeload(_ proposal: DeloadProposal) throws -> ReviewApplication {
        guard let exerciseID = proposal.exerciseID else { throw CoachChatApplyError.notValidated }
        guard let exercise = fetchExerciseModel(id: exerciseID) else {
            throw CoachChatApplyError.exerciseMissing(proposal.exerciseName ?? "That exercise")
        }
        guard let current = coachChatWorkingWeightKg(exerciseID: exerciseID),
              let applied = applyCoachDeload(
                  exerciseID: exerciseID, exerciseName: exercise.name,
                  toWeightKg: current * (1 - proposal.percent / 100)
              ) else { throw CoachChatApplyError.routineMissing }
        return ReviewApplication(deload: applied, message: "\(exercise.name) deloaded")
    }

    /// The weight a deload cuts from: the last logged working set, else the first working
    /// planned target on any routine that programs the exercise. Nil when neither exists.
    func coachChatWorkingWeightKg(exerciseID: UUID) -> Double? {
        if let logged = exerciseHistory(exerciseID: exerciseID, limit: 1).first?.workingSets.first?.weightKg,
           logged > 0 {
            return logged
        }
        let slots = fetch(FetchDescriptor<RoutineExerciseModel>()).filter {
            $0.exercise?.id == exerciseID && $0.routine?.isArchived == false
        }
        let planned = slots.flatMap { $0.plannedSets ?? [] }
            .filter { $0.setKind.countsTowardStats }
            .sorted { $0.order < $1.order }
        return planned.compactMap(\.targetWeightKg).first { $0 > 0 }
    }

    // MARK: - Swap

    /// Replaces the outgoing exercise's slot with the incoming one, keeping its sets, rest and
    /// superset group. The snapshot carries the stall memory so Undo restores it too.
    private func applySwap(_ proposal: SwapProposal) throws -> ReviewApplication {
        guard let from = proposal.fromExerciseID, let to = proposal.toExerciseID else {
            throw CoachChatApplyError.notValidated
        }
        guard let model = fetchRoutineModel(id: proposal.routineID), !model.isArchived,
              let snapshot = routineSnapshot(model) else { throw CoachChatApplyError.routineMissing }
        guard fetchExerciseModel(id: to) != nil else {
            throw CoachChatApplyError.exerciseMissing(proposal.toExerciseName ?? "That exercise")
        }
        guard let index = snapshot.drafts.firstIndex(where: { $0.exerciseID == from }) else {
            throw CoachChatApplyError.exerciseMissing(proposal.fromExerciseName ?? "That exercise")
        }
        var drafts = snapshot.drafts
        drafts[index].exerciseID = to
        drafts[index].trainingMaxKg = nil
        resave(snapshot, drafts: drafts)
        let message = "Swapped \(proposal.fromExerciseName ?? "exercise") for "
            + "\(proposal.toExerciseName ?? "exercise") in \(snapshot.name)"
        return ReviewApplication(previousRoutines: [snapshot], message: message)
    }
}

extension Preferences.TrainingGoal {
    /// The coach's goal vocabulary for the onboarding goal ("Muscle" is hypertrophy).
    var coachGoal: GymCore.TrainingGoal {
        switch self {
        case .strength: .strength
        case .muscle: .hypertrophy
        case .general: .general
        }
    }
}

extension CoachChatConfiguration {
    /// The chat preferences as the value the engine takes.
    @MainActor
    init(preferences: Preferences) {
        self.init(
            modelID: preferences.coachModelID, reviewerModelID: preferences.coachReviewerModelID,
            consentGiven: preferences.coachChatConsentGiven
        )
    }
}
