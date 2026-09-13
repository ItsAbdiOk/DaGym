import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// D2: `planDeloadWeek()` used to create a `weeks: 1` program, whose week index
/// (`days / 7 % 1 + 1`) is always 1 — every routine session was prescribed at deload load
/// forever, and the program the user was actually running stayed deactivated. The fix makes
/// it a 2-week program (deload, then normal) and hands the previous program back control once
/// its single deload week is over.
@MainActor
@Suite("Deload week")
struct DeloadWeekTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        return WorkoutStore(context: context)
    }

    private func fetchProgram(_ store: WorkoutStore, id: UUID) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? store.context.fetch(descriptor))?.first
    }

    @Test("planDeloadWeek's week 2 is normal, not another deload")
    func weekTwoIsNormal() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let routineID = try #require(store.routines().first?.id)

        store.planDeloadWeek()
        let active = try #require(store.activeProgramModel())
        active.startedAt = Calendar.current.date(byAdding: .day, value: -8, to: Date())
        store.save()

        #expect(store.currentWeekKind(forRoutineID: routineID) != .deload)
    }

    @Test("once the deload week expires, the previously active program resumes")
    func previousProgramResumes() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = store.createProgram(from: .pushPullLegs)
        store.startProgram(id: original.id)

        store.planDeloadWeek()
        let deload = try #require(store.activeProgramModel())
        #expect(deload.name == "Deload Week")
        deload.startedAt = Calendar.current.date(byAdding: .day, value: -8, to: Date())
        store.save()

        let resumed = try #require(store.activeProgramModel())
        #expect(resumed.id == original.id)
        #expect(resumed.isActive)

        let deloadModel = try #require(fetchProgram(store, id: deload.id))
        #expect(!deloadModel.isActive)
    }

    @Test("during its own single week, the deload program stays active")
    func deloadStaysActiveDuringItsOwnWeek() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = store.createProgram(from: .pushPullLegs)
        store.startProgram(id: original.id)

        store.planDeloadWeek()
        let active = try #require(store.activeProgramModel())
        #expect(active.name == "Deload Week")
        #expect(active.isActive)
    }
}
