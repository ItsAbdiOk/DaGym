import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// `WorkoutStore.adoptStarterPlan` (OpenGym parity 36): the one-tap path Home's empty card and
/// the Routines tab's "Load a starter plan" share — seeds the plan's routines, starts its
/// program, and never stacks a second copy of the same plan.
@MainActor
@Suite("Starter plan adoption")
struct StarterPlanAdoptionTests {
    @Test("from an empty store, adopting seeds exactly the plan's routines and starts the program")
    func adoptsFromEmpty() throws {
        let store = try makeStore(seed: .firstLaunch)
        #expect(store.routines().isEmpty)

        let program = try #require(store.adoptStarterPlan(.pushPullLegs))

        #expect(program.isActive)
        #expect(program.startedAt != nil)
        #expect(Set(store.routines().map(\.name)) == ["Push A", "Pull B", "Legs"])
        #expect(store.programs().map(\.name) == ["Push/Pull/Legs"], "the Programs tab shows it")
    }

    @Test("picking the same plan twice reuses the program instead of duplicating it")
    func twiceIsOnce() throws {
        let store = try makeStore(seed: .firstLaunch)
        let first = try #require(store.adoptStarterPlan(.pushPullLegs))
        let second = try #require(store.adoptStarterPlan(.pushPullLegs))

        #expect(first.id == second.id)
        #expect(store.programs().count == 1)
        #expect(store.routines().count == 3, "no second Push A either")
        #expect(second.isActive)
    }

    @Test("a different plan is its own program, and takes over as the active one")
    func differentPlanIsSeparate() throws {
        let store = try makeStore(seed: .firstLaunch)
        let ppl = try #require(store.adoptStarterPlan(.pushPullLegs))
        let upperLower = try #require(store.adoptStarterPlan(.upperLower))

        #expect(ppl.id != upperLower.id)
        let programs = store.programs()
        #expect(programs.count == 2)
        #expect(programs.filter(\.isActive).map(\.id) == [upperLower.id])
        // PPL's three plus Upper/Lower's four.
        #expect(store.routines().count == 7)
    }

    @Test("a completed program is not resurrected; the plan is created afresh")
    func completedIsNotReused() throws {
        let store = try makeStore(seed: .firstLaunch)
        let first = try #require(store.adoptStarterPlan(.fiveByFive))
        store.completeProgram(id: first.id)

        let again = try #require(store.adoptStarterPlan(.fiveByFive))
        #expect(again.id != first.id)
        #expect(store.programs().count == 2)
        #expect(store.routines().count == 3, "the routines themselves are still reused")
    }

    @Test("a starter the lifter renamed still counts as the plan's day")
    func renamedStarterIsReused() throws {
        let store = try makeStore(seed: .firstLaunch)
        let first = try #require(store.adoptStarterPlan(.fullBody))
        let fullBodyA = try #require(store.routines().first { $0.name == "Full Body A" })
        let drafts = try #require(store.routineDrafts(id: fullBodyA.id)).drafts
        store.saveRoutine(id: fullBodyA.id, name: "Monday", exercises: drafts)

        let again = try #require(store.adoptStarterPlan(.fullBody))
        #expect(again.id == first.id)
        #expect(store.routines().count == 3)
    }

    @Test("a stocked store (every starter already present) adds no routines")
    func stockedStoreAddsNothing() throws {
        let store = try makeStore(seed: .stocked)
        let before = store.routines().count

        #expect(store.adoptStarterPlan(.upperLower) != nil)
        #expect(store.routines().count == before)
    }
}
