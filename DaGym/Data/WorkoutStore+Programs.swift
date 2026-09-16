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
    /// 1-based week within the block, and 1-based repetition of the block — nil for a program
    /// that hasn't started or has run its `ProgramCycle.maxCycles` repetitions. `ProgramsView`
    /// shows these; without them the lifter had no way to see which week they were in, which is
    /// the one thing a multi-week program is for.
    var currentWeek: Int?
    var currentCycle: Int?
    var isFinished = false

    /// The kind of week the program is in right now, for the week strip's highlight.
    var currentWeekKind: ProgramWeekKind? {
        guard let currentWeek else { return nil }
        return ProgramInfo.week(at: currentWeek, in: programWeeks)?.kind
    }

    /// `programWeeks` may not have exactly `weeks` entries (a `.gymplan` import can define
    /// fewer), so an index that has no exact match wraps into whatever weeks the program does
    /// define rather than reporting "no week kind at all".
    static func week(at index: Int, in weeks: [ProgramWeekInfo]) -> ProgramWeekInfo? {
        guard !weeks.isEmpty else { return nil }
        if let exact = weeks.first(where: { $0.index == index }) { return exact }
        return weeks[(max(1, index) - 1) % weeks.count]
    }
}

/// Starter program templates built from `RoutineSeeder`'s starters — "Push A"/"Pull B"/"Legs",
/// Upper/Lower A/B, Full Body A/B/C, 5×5 A/B/C — so a program can be created without an
/// exercise-picking flow. The app ships no routines: `createProgram(from:)` seeds the ones the
/// program cycles when it is created.
enum StarterProgramKind: String, CaseIterable, Identifiable, Hashable {
    case pushPullLegs = "Push/Pull/Legs"
    case upperLower = "Upper/Lower"
    case fullBody = "Full Body"
    case fiveByFive = "5×5"

    var id: String { rawValue }

    /// Routine names to cycle through, in day order — `RoutineSeeder` starters, seeded on
    /// demand and matched by starter id or name when `createProgram(from:)` builds the program.
    var routineNames: [String] {
        switch self {
        case .pushPullLegs: ["Push A", "Pull B", "Legs"]
        case .upperLower: ["Upper A", "Lower A", "Upper B", "Lower B"]
        case .fullBody: ["Full Body A", "Full Body B", "Full Body C"]
        case .fiveByFive: ["5×5 A", "5×5 B", "5×5 C"]
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
    func programs(now: Date = Date(), calendar: Calendar = .current) -> [ProgramInfo] {
        // Same expiry check `activeProgramModel()` runs, so the Programmes screen and the session
        // that `startWorkout` builds agree on which programme is active. Without it an expired
        // deload shim was still listed as the active programme (in its week 2) right up until
        // some *other* screen happened to call `activeProgramModel()` — while `startWorkout` had
        // already handed control back to the programme the deload interrupted.
        resumeProgramIfDeloadExpired(now: now, calendar: calendar)
        pruneAbandonedDeloadPrograms()
        let descriptor = FetchDescriptor<ProgramModel>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return fetch(descriptor).map { programInfo($0, now: now, calendar: calendar) }
    }

    /// Builds `kind`'s program from its starter routines, seeding whichever of them the store
    /// doesn't have yet (`RoutineSeeder.seedStarters`) — the app ships no routines, so from an
    /// empty store this writes exactly the program's days. A starter the lifter already has —
    /// by its starter id, so a renamed or edited copy counts — is reused, not duplicated. Nil,
    /// and nothing inserted, only when a day can't be built at all (its lifts are missing from
    /// the library): a program cycling the wrong days is worse than no program. A routine
    /// deleted *after* the program was created is not re-seeded; the program just loses that day.
    @discardableResult
    func createProgram(from kind: StarterProgramKind) -> ProgramInfo? {
        RoutineSeeder.seedStarters(kind.routineNames, store: self)
        let live = fetch(FetchDescriptor<RoutineModel>()).filter { !$0.isMergedAway }
        let routineIDs = kind.routineNames.compactMap { name -> UUID? in
            let byStarterID = RoutineSeeder.starterIDs[name].flatMap { id in
                live.first { $0.importedFromID == id }
            }
            return (byStarterID ?? live.first { $0.name == name })?.id
        }
        guard routineIDs.count == kind.routineNames.count else { return nil }
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
    func startProgram(id: UUID, now: Date = Date()) -> ProgramInfo? {
        guard let model = fetchProgramModel(id: id) else { return nil }
        for other in fetch(FetchDescriptor<ProgramModel>()) { other.isActive = false }
        model.isActive = true
        model.startedAt = now
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

    /// 1-based week index in the program's cycle, counted in **whole calendar weeks** from the
    /// week `startedAt` falls in (see `GymCore.ProgramCycle`); 1 for a program that hasn't
    /// started, and held at the last week once the program has run its repetitions out.
    ///
    /// `now`/`calendar` are parameters rather than `Date()`/`Calendar.current` reached for
    /// inside: none of this was testable before, and the week boundary moved with the clock and
    /// the timezone instead of sitting on the lifter's own week start.
    func currentWeek(for program: ProgramModel, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let startedAt = program.startedAt, program.weeks > 0 else { return 1 }
        let position = ProgramCycle.position(
            startedAt: startedAt, now: now, weeks: program.weeks, calendar: calendar
        )
        return position?.week ?? program.weeks
    }

    /// The active program's current week index for `routineID`, or nil when no active program
    /// includes it — the `weekInCycle` the TM rule needs.
    func weekInCycle(forRoutineID routineID: UUID) -> Int? {
        weekInCycle(forRoutineID: routineID, activeProgram: activeProgramModel())
    }

    /// The active program's current week kind for `routineID`, or nil when no active program
    /// includes it. `startWorkout` uses this to flag/prescribe a planned deload week.
    func currentWeekKind(forRoutineID routineID: UUID) -> ProgramWeekKind? {
        currentWeekKind(forRoutineID: routineID, activeProgram: activeProgramModel())
    }

    /// The same three program lookups against an `activeProgramModel()` the caller already
    /// holds. `startWorkout` and friends fetch the active program once for the whole session and
    /// call these, rather than paying `activeProgramModel()`'s two queries per exercise for an
    /// answer that cannot differ between them.
    func weekInCycle(
        forRoutineID routineID: UUID, activeProgram: ProgramModel?, now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        guard let program = activeProgram, program.routineIDs.contains(routineID),
              let startedAt = program.startedAt else { return nil }
        return ProgramCycle.position(
            startedAt: startedAt, now: now, weeks: program.weeks, calendar: calendar
        )?.week
    }

    /// The week kind for `routineID` right now.
    ///
    /// Wraps into whatever weeks the program actually defines when `programWeeks.count` doesn't
    /// match `weeks` — a `.gymplan` import can produce that, and the old exact-index lookup
    /// then returned nil, silently dropping every planned deload the plan described.
    func currentWeekKind(
        forRoutineID routineID: UUID, activeProgram: ProgramModel?, now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgramWeekKind? {
        guard let program = activeProgram,
              let week = weekInCycle(
                  forRoutineID: routineID, activeProgram: program, now: now, calendar: calendar
              ) else { return nil }
        let weeks = (program.programWeeks ?? []).sorted { $0.index < $1.index }
        guard !weeks.isEmpty else { return nil }
        if let exact = weeks.first(where: { $0.index == week }) { return exact.weekKind }
        return weeks[(max(1, week) - 1) % weeks.count].weekKind
    }

    func activeProgramModel(now: Date = Date(), calendar: Calendar = .current) -> ProgramModel? {
        resumeProgramIfDeloadExpired(now: now, calendar: calendar)
        let descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.isActive })
        guard let active = fetchFirst(descriptor) else { return nil }
        guard let startedAt = active.startedAt,
              ProgramCycle.isFinished(
                  startedAt: startedAt, now: now, weeks: active.weeks, calendar: calendar
              ) else { return active }
        // A program that has repeated its own block `ProgramCycle.maxCycles` times is over.
        // Left running, its week index wrapped forever and its cycle index climbed without
        // bound, so the training-max rule kept bumping every `weeks` weeks indefinitely.
        active.isActive = false
        active.completedAt = active.completedAt ?? now
        save()
        return nil
    }

    /// A planned deload week (`planDeloadWeek()`) is a 2-week program — week 1 deload, week 2
    /// normal — so that a lifter who never reopens the app isn't stuck on deload load forever.
    /// Once a whole calendar week has passed since it started, this deactivates it and hands
    /// control back to the program it interrupted (see `interruptedProgram()`), shifted forward
    /// by the weeks the deload consumed, so progression resumes exactly where it left off.
    private func resumeProgramIfDeloadExpired(now: Date, calendar: Calendar) {
        let descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.isActive })
        guard let active = fetchFirst(descriptor), active.name == WorkoutStore.deloadProgramName,
              let deloadStart = active.startedAt else { return }
        let elapsed = ProgramCycle.weeksElapsed(from: deloadStart, to: now, calendar: calendar)
        guard elapsed >= 1 else { return }
        active.isActive = false
        active.completedAt = now
        if let resumed = interruptedProgram() {
            resumed.isActive = true
            // The deload ate `elapsed` calendar weeks of the interrupted program's own cycle.
            // Without this shift a 4-week block interrupted in week 3 came back in week 4 —
            // which is that block's *own* deload — so the lifter got two deload weeks back to
            // back and never trained week 3 at all.
            resumed.startedAt = (resumed.startedAt).map {
                ProgramCycle.shifted($0, byWeeks: elapsed, notPast: now, calendar: calendar)
            }
            resumed.completedAt = nil
        }
        pruneAbandonedDeloadPrograms()
        save()
    }

    /// The real program a planned deload interrupted: the most recently started program that
    /// isn't a deload shim and hasn't been completed.
    ///
    /// Derived rather than remembered. The pointer used to live in `UserDefaults.standard`,
    /// which meant a second device never resumed anything, and tapping "Plan a deload week"
    /// while a deload was already running overwrote it with nothing — so the original program
    /// stayed deactivated forever.
    private func interruptedProgram() -> ProgramModel? {
        fetch(FetchDescriptor<ProgramModel>())
            .filter { $0.name != WorkoutStore.deloadProgramName && $0.completedAt == nil }
            .compactMap { model in model.startedAt.map { (model, $0) } }
            .max { $0.1 < $1.1 }?.0
    }

    /// Deletes deload shims that were superseded before they ever expired — what a second tap
    /// on "Plan a deload week" leaves behind. An expired one (`completedAt` set) is kept, since
    /// it is the record of a deload the lifter actually took.
    ///
    /// Called from `programs()` (the only screen that shows the clutter) and from the resume
    /// path — deliberately *not* from `activeProgramModel()`, which is on `startWorkout`'s hot
    /// path and is held to a fixed query count by `WorkoutStoreStartPerformanceTests`.
    private func pruneAbandonedDeloadPrograms() {
        let name = WorkoutStore.deloadProgramName
        let abandoned = fetch(FetchDescriptor<ProgramModel>()).filter {
            $0.name == name && !$0.isActive && $0.completedAt == nil
        }
        guard !abandoned.isEmpty else { return }
        for model in abandoned { context.delete(model) }
        save()
    }

    private func fetchProgramModel(id: UUID) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetchFirst(descriptor)
    }

    private func programInfo(
        _ model: ProgramModel, now: Date = Date(), calendar: Calendar = .current
    ) -> ProgramInfo {
        let weeks = (model.programWeeks ?? []).sorted { $0.index < $1.index }.map {
            ProgramWeekInfo(id: $0.id, index: $0.index, kind: $0.weekKind)
        }
        let position = model.startedAt.flatMap {
            ProgramCycle.position(startedAt: $0, now: now, weeks: model.weeks, calendar: calendar)
        }
        let finished = model.startedAt.map {
            ProgramCycle.isFinished(startedAt: $0, now: now, weeks: model.weeks, calendar: calendar)
        } ?? false
        return ProgramInfo(
            id: model.id, name: model.name, weeks: model.weeks, startedAt: model.startedAt,
            completedAt: model.completedAt, isActive: model.isActive, routineIDs: model.routineIDs,
            programWeeks: weeks, currentWeek: position?.week, currentCycle: position?.cycle,
            isFinished: finished
        )
    }
}
