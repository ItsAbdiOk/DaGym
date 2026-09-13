import Foundation
import GymCore
import SwiftData

/// One program week, for `ProgramsView`'s week strip.
struct ProgramWeekInfo: Identifiable, Hashable {
    var id: UUID
    var index: Int
    var kind: ProgramWeekKind
}

/// A multi-week program (plan.md §6.5), for `ProgramsView`.
struct ProgramInfo: Identifiable, Hashable {
    var id: UUID
    var name: String
    var weeks: Int
    var startedAt: Date?
    var completedAt: Date?
    var isActive: Bool
    var routineIDs: [UUID]
    var programWeeks: [ProgramWeekInfo]
}

/// Starter program templates built from the seeded routines (`RoutineSeeder`'s "Push A"/"Pull
/// B"/"Legs"), so a program can be created without an exercise-picking flow.
enum StarterProgramKind: String, CaseIterable, Identifiable, Hashable {
    case pushPullLegs = "Push/Pull/Legs"
    case upperLower = "Upper/Lower"
    case fullBody = "Full Body"
    case fiveByFive = "5×5"

    var id: String { rawValue }

    /// Routine names to cycle through, in day order — matched against `WorkoutStore.routines()`
    /// by name; a name that isn't found is simply skipped.
    var routineNames: [String] {
        switch self {
        case .pushPullLegs: ["Push A", "Pull B", "Legs"]
        case .upperLower: ["Push A", "Legs"]
        case .fullBody: ["Push A", "Pull B", "Legs"]
        case .fiveByFive: ["Push A", "Legs"]
        }
    }

    var weeks: Int { self == .fiveByFive ? 3 : 4 }
}

enum StarterPrograms {
    /// One deload week at the end of the cycle, every other week normal.
    static func weekKinds(for kind: StarterProgramKind) -> [ProgramWeekKind] {
        var kinds = Array(repeating: ProgramWeekKind.normal, count: max(0, kind.weeks - 1))
        kinds.append(.deload)
        return kinds
    }
}

extension WorkoutStore {
    func programs() -> [ProgramInfo] {
        let descriptor = FetchDescriptor<ProgramModel>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(programInfo)
    }

    @discardableResult
    func createProgram(from kind: StarterProgramKind) -> ProgramInfo {
        let existing = routines()
        let routineIDs = kind.routineNames.compactMap { name in existing.first { $0.name == name }?.id }
        let model = ProgramModel(name: kind.rawValue, weeks: kind.weeks)
        model.routineIDs = routineIDs
        context.insert(model)
        model.programWeeks = StarterPrograms.weekKinds(for: kind).enumerated().map { index, weekKind in
            let week = ProgramWeekModel(index: index + 1, kind: weekKind.rawValue, program: model)
            context.insert(week)
            return week
        }
        save()
        return programInfo(model)
    }

    /// Starts a program, deactivating every other one — only one can be active at a time.
    @discardableResult
    func startProgram(id: UUID) -> ProgramInfo? {
        guard let model = fetchProgramModel(id: id) else { return nil }
        for other in (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? [] { other.isActive = false }
        model.isActive = true
        model.startedAt = Date()
        model.completedAt = nil
        save()
        return programInfo(model)
    }

    func stopProgram(id: UUID) {
        guard let model = fetchProgramModel(id: id) else { return }
        model.isActive = false
        save()
    }

    func completeProgram(id: UUID) {
        guard let model = fetchProgramModel(id: id) else { return }
        model.isActive = false
        model.completedAt = Date()
        save()
    }

    /// 1-based week index in the program's cycle from `startedAt`, wrapping every `weeks` weeks;
    /// 1 for a program that hasn't started.
    func currentWeek(for program: ProgramModel) -> Int {
        guard let startedAt = program.startedAt, program.weeks > 0 else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: startedAt, to: Date()).day ?? 0
        return (max(0, days / 7) % program.weeks) + 1
    }

    /// The active program's current week index for `routineID`, or nil when no active program
    /// includes it — the `weekInCycle` the TM rule needs.
    func weekInCycle(forRoutineID routineID: UUID) -> Int? {
        guard let program = activeProgramModel(), program.routineIDs.contains(routineID) else { return nil }
        return currentWeek(for: program)
    }

    /// The active program's current week kind for `routineID`, or nil when no active program
    /// includes it. `startWorkout` uses this to flag/prescribe a planned deload week.
    func currentWeekKind(forRoutineID routineID: UUID) -> ProgramWeekKind? {
        guard let program = activeProgramModel(), program.routineIDs.contains(routineID) else { return nil }
        let week = currentWeek(for: program)
        return (program.programWeeks ?? []).first { $0.index == week }?.weekKind
    }

    func activeProgramModel() -> ProgramModel? {
        resumeProgramIfDeloadExpired()
        let descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.isActive })
        return (try? context.fetch(descriptor))?.first
    }

    /// A planned deload week (`planDeloadWeek()`) is a 2-week program — week 1 deload, week 2
    /// normal — so that a lifter who never reopens the app isn't stuck on deload load forever.
    /// Once its own week index moves past week 1, this deactivates it and reactivates whichever
    /// program was active before it (persisted by `planDeloadWeek()`), so progression on the
    /// user's real program resumes without them having to do anything.
    private func resumeProgramIfDeloadExpired() {
        let descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.isActive })
        guard let active = (try? context.fetch(descriptor))?.first,
              active.name == WorkoutStore.deloadProgramName, currentWeek(for: active) > 1 else { return }
        active.isActive = false
        active.completedAt = Date()
        let defaults = UserDefaults.standard
        if let idString = defaults.string(forKey: WorkoutStore.deloadPreviousProgramIDKey),
           let id = UUID(uuidString: idString), let resumed = fetchProgramModel(id: id) {
            resumed.isActive = true
        }
        defaults.removeObject(forKey: WorkoutStore.deloadPreviousProgramIDKey)
        save()
    }

    private func fetchProgramModel(id: UUID) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func programInfo(_ model: ProgramModel) -> ProgramInfo {
        let weeks = (model.programWeeks ?? []).sorted { $0.index < $1.index }.map {
            ProgramWeekInfo(id: $0.id, index: $0.index, kind: $0.weekKind)
        }
        return ProgramInfo(
            id: model.id, name: model.name, weeks: model.weeks, startedAt: model.startedAt,
            completedAt: model.completedAt, isActive: model.isActive, routineIDs: model.routineIDs,
            programWeeks: weeks
        )
    }
}
