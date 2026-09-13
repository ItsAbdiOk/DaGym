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

    @Test("currentWeek wraps every `weeks` weeks from startedAt")
    func weekComputation() throws {
        let store = try makeStore()
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let created = try #require(store.createProgram(from: .pushPullLegs))
        guard let model = store.programs().first(where: { $0.id == created.id }) else {
            Issue.record("program not found")
            return
        }
        let programModel = try #require(fetchProgram(store, id: model.id))

        programModel.startedAt = Date()
        #expect(store.currentWeek(for: programModel) == 1)

        programModel.startedAt = Calendar.current.date(byAdding: .day, value: -8, to: Date())
        #expect(store.currentWeek(for: programModel) == 2)

        // Wraps back to week 1 after a full 4-week cycle.
        programModel.startedAt = Calendar.current.date(byAdding: .day, value: -28, to: Date())
        #expect(store.currentWeek(for: programModel) == 1)
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

    private func fetchProgram(_ store: WorkoutStore, id: UUID) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? store.context.fetch(descriptor))?.first
    }
}
