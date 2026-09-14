import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore programs")
struct WorkoutStoreProgramTests {
    /// `RoutineSeeder` looks starter exercises up by name in the seeded library, so the
    /// library has to exist first or no routine (and so no program slot) is created.
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        return WorkoutStore(context: context)
    }

    @Test("a starter program is built from the seeded routine names, with a deload last week")
    func starterProgramCreation() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)

        let program = try #require(store.createProgram(from: .pushPullLegs))

        #expect(program.name == "Push/Pull/Legs")
        #expect(program.routineIDs.count == 3)
        #expect(program.programWeeks.map(\.kind) == [.normal, .normal, .normal, .deload])
    }

    @Test("currentWeek counts whole calendar weeks and wraps every `weeks` weeks")
    func weekComputation() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let created = try #require(store.createProgram(from: .pushPullLegs))
        let programModel = try #require(fetchProgram(store, id: created.id))
        let calendar = Self.calendar()
        let now = Self.date(2026, 2, 4) // Wednesday

        programModel.startedAt = now
        #expect(store.currentWeek(for: programModel, now: now, calendar: calendar) == 1)

        programModel.startedAt = Self.date(2026, 1, 28) // the calendar week before
        #expect(store.currentWeek(for: programModel, now: now, calendar: calendar) == 2)

        // Wraps back to week 1 after a full 4-week cycle.
        programModel.startedAt = Self.date(2026, 1, 7)
        #expect(store.currentWeek(for: programModel, now: now, calendar: calendar) == 1)
    }

    /// The defect: `dateComponents([.day], from: startedAt, to: now) / 7` anchored the week
    /// boundary to the *time of day* the program was started, so a Wednesday-21:30 start put
    /// that same Wednesday's 18:00 and 22:00 sessions in different program weeks and made the
    /// planned deload straddle two calendar weeks.
    @Test("a Wednesday-evening start keeps the whole of that calendar week in week 1")
    func midWeekEveningStart() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let created = try #require(store.createProgram(from: .pushPullLegs))
        let programModel = try #require(fetchProgram(store, id: created.id))
        let calendar = Self.calendar()
        programModel.startedAt = Self.date(2026, 1, 7, hour: 21, minute: 30)

        for hour in [18, 22] {
            let moment = Self.date(2026, 1, 7, hour: hour)
            #expect(store.currentWeek(for: programModel, now: moment, calendar: calendar) == 1)
        }
        #expect(
            store.currentWeek(for: programModel, now: Self.date(2026, 1, 11), calendar: calendar) == 1,
            "the Sunday that closes the same calendar week is still week 1"
        )
        #expect(
            store.currentWeek(for: programModel, now: Self.date(2026, 1, 12), calendar: calendar) == 2
        )
    }

    /// Left uncapped, the week index wrapped forever and the cycle index climbed without bound,
    /// so the training-max rule kept bumping every four weeks indefinitely.
    @Test("a program that has run its cycles out completes instead of wrapping forever")
    func programsEventuallyEnd() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let created = try #require(store.createProgram(from: .pushPullLegs))
        let routineID = try #require(created.routineIDs.first)
        let programModel = try #require(fetchProgram(store, id: created.id))
        let calendar = Self.calendar()
        programModel.startedAt = Self.date(2026, 1, 5)
        programModel.isActive = true
        store.save()

        // 4 weeks × ProgramCycle.maxCycles later.
        let after = try #require(calendar.date(
            byAdding: .day, value: 4 * ProgramCycle.maxCycles * 7, to: Self.date(2026, 1, 5)
        ))
        #expect(store.activeProgramModel(now: after, calendar: calendar) == nil)
        let completed = try #require(fetchProgram(store, id: created.id))
        #expect(!completed.isActive)
        #expect(completed.completedAt != nil)
        #expect(store.weekInCycle(
            forRoutineID: routineID, activeProgram: completed, now: after, calendar: calendar
        ) == nil)
    }

    /// An imported `.gymplan` can define fewer week rows than `weeks`. The old exact-index
    /// lookup then returned nil, silently dropping every planned deload the plan described.
    @Test("a week count that doesn't match the week rows still resolves a week kind")
    func mismatchedWeekRowsStillResolve() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let routineID = try #require(store.routines().first?.id)
        let calendar = Self.calendar()
        let program = ProgramModel(
            name: "Imported", weeks: 4, startedAt: Self.date(2026, 1, 5), isActive: true
        )
        program.routineIDs = [routineID]
        store.context.insert(program)
        // Only two week rows for a four-week program.
        let normal = ProgramWeekModel(index: 1, kind: ProgramWeekKind.normal.rawValue, program: program)
        let deload = ProgramWeekModel(index: 2, kind: ProgramWeekKind.deload.rawValue, program: program)
        store.context.insert(normal)
        store.context.insert(deload)
        program.programWeeks = [normal, deload]
        store.save()

        let week3 = Self.date(2026, 1, 19)
        #expect(store.weekInCycle(
            forRoutineID: routineID, activeProgram: program, now: week3, calendar: calendar
        ) == 3)
        #expect(store.currentWeekKind(
            forRoutineID: routineID, activeProgram: program, now: week3, calendar: calendar
        ) == .normal)
        let week4 = Self.date(2026, 1, 26)
        #expect(store.currentWeekKind(
            forRoutineID: routineID, activeProgram: program, now: week4, calendar: calendar
        ) == .deload)
    }

    /// `ProgramsView` shows this; without it the lifter had no way to see which week of their
    /// own program they were in.
    @Test("ProgramInfo reports the current week and cycle")
    func programInfoReportsPosition() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let created = try #require(store.createProgram(from: .pushPullLegs))
        let programModel = try #require(fetchProgram(store, id: created.id))
        let calendar = Self.calendar()
        programModel.startedAt = Self.date(2026, 1, 5)
        store.save()

        let info = try #require(
            store.programs(now: Self.date(2026, 1, 21), calendar: calendar).first { $0.id == created.id }
        )
        #expect(info.currentWeek == 3)
        #expect(info.currentCycle == 1)
        #expect(info.currentWeekKind == .normal)

        let notStarted = try #require(
            store.programs(now: Self.date(2026, 1, 1), calendar: calendar).first { $0.id == created.id }
        )
        #expect(notStarted.currentWeek == 1, "a program starting later reads as its first week")
    }

    @Test("starting a program during its deload week flags the routine's next session")
    func deloadWeekFlag() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let created = try #require(store.createProgram(from: .pushPullLegs))
        let routineID = try #require(created.routineIDs.first)
        let programModel = try #require(fetchProgram(store, id: created.id))
        // 3 weeks (21 days) back lands in the 4th (deload) week of the cycle.
        programModel.startedAt = Calendar.current.date(byAdding: .day, value: -21, to: Date())
        programModel.isActive = true
        store.save()

        #expect(store.currentWeekKind(forRoutineID: routineID) == .deload)

        let session = store.startWorkout(routineID: routineID)
        let allDeload = session.exercises.allSatisfy { $0.wasPlannedDeload }
        #expect(allDeload)
        store.discard(session: session)
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private static func date(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar().date(from: components) ?? Date()
    }

    private func fetchProgram(_ store: WorkoutStore, id: UUID) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? store.context.fetch(descriptor))?.first
    }
}
