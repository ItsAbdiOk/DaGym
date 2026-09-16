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
    private func fetchProgram(_ store: WorkoutStore, id: UUID) -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? store.context.fetch(descriptor))?.first
    }

    @Test("planDeloadWeek's week 2 is normal, not another deload")
    func weekTwoIsNormal() throws {
        let store = try makeStore(seed: .exercises)
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
        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = try #require(store.createProgram(from: .pushPullLegs))
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
        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = try #require(store.createProgram(from: .pushPullLegs))
        store.startProgram(id: original.id)

        store.planDeloadWeek()
        let active = try #require(store.activeProgramModel())
        #expect(active.name == "Deload Week")
        #expect(active.isActive)
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar().date(from: components) ?? Date()
    }

    /// The defect, in the reviewer's own numbers: a 4-week PPL started Monday 7 Sep with a
    /// deload planned on the 21st used to resume on the 28th at **week 4** — which is the
    /// block's own deload — so the lifter got two deload weeks back to back and never trained
    /// week 3 at all. The interrupted program's `startedAt` now moves forward by however many
    /// weeks the deload consumed, so it comes back where it left off.
    @Test("resuming after a deload doesn't skip the interrupted week or stack two deloads")
    func resumeShiftsTheInterruptedProgramForward() throws {
        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = try #require(store.createProgram(from: .pushPullLegs))
        let routineID = try #require(original.routineIDs.first)
        let calendar = Self.calendar()
        let programModel = try #require(fetchProgram(store, id: original.id))
        programModel.startedAt = Self.date(2026, 9, 7) // Monday, week 1
        programModel.isActive = true
        store.save()

        // Week 3 of the block: plan a deload.
        store.planDeloadWeek()
        let deloadID = try #require(store.activeProgramModel()?.id)
        let deload = try #require(fetchProgram(store, id: deloadID))
        deload.startedAt = Self.date(2026, 9, 21)
        store.save()

        // Monday the 28th: the deload week is over.
        let resumeDay = Self.date(2026, 9, 28)
        let resumed = try #require(store.activeProgramModel(now: resumeDay, calendar: calendar))
        #expect(resumed.id == original.id)
        #expect(
            store.currentWeek(for: resumed, now: resumeDay, calendar: calendar) == 3,
            "it resumes at the week the deload interrupted, not at the block's own deload"
        )
        #expect(store.currentWeekKind(
            forRoutineID: routineID, activeProgram: resumed, now: resumeDay, calendar: calendar
        ) == .normal)
    }

    /// Tapping "Plan a deload week" twice used to drop the saved previous-program id (it was
    /// read back as the deload program's own id and cleared), so the real program stayed
    /// deactivated forever — and each tap left another "Deload Week" row in the programs list.
    @Test("a second deload tap still resumes the real program, and leaves no extra rows")
    func doubleDeloadTap() throws {
        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = try #require(store.createProgram(from: .pushPullLegs))
        store.startProgram(id: original.id, now: Self.date(2026, 9, 7))
        let calendar = Self.calendar()

        store.planDeloadWeek()
        store.planDeloadWeek()

        let active = try #require(store.activeProgramModel())
        active.startedAt = Self.date(2026, 9, 21)
        store.save()

        let resumeDay = Self.date(2026, 9, 28)
        let resumed = try #require(store.activeProgramModel(now: resumeDay, calendar: calendar))
        #expect(resumed.id == original.id, "the real program must still come back")

        let deloadRows = store.programs().filter { $0.name == "Deload Week" }
        #expect(deloadRows.count == 1, "the abandoned shim from the first tap is cleaned up")
    }

    /// `planDeloadWeek()` used to write the interrupted programme's id to
    /// `UserDefaults.standard`. That key is gone: it never reached a second device (which shares
    /// the SwiftData store through CloudKit but not the defaults), so resume silently did
    /// nothing there. Leaving a stale value from an older build behind must change nothing.
    @Test("a stale UserDefaults pointer from an older build has no effect on resuming")
    func staleDefaultsPointerIsIgnored() throws {
        let key = "deloadPreviousProgramID"
        let stale = UUID().uuidString
        UserDefaults.standard.set(stale, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = try #require(store.createProgram(from: .pushPullLegs))
        store.startProgram(id: original.id)

        store.planDeloadWeek()
        // Neither written nor cleared any more — nothing in this path reads or writes defaults.
        #expect(UserDefaults.standard.string(forKey: key) == stale)

        let deload = try #require(store.activeProgramModel())
        deload.startedAt = Calendar.current.date(byAdding: .day, value: -8, to: Date())
        store.save()

        let resumed = try #require(store.activeProgramModel())
        #expect(resumed.id == original.id, "the pointer is derived from the programmes themselves")
    }

    /// `programs()` (the Programmes screen) and `activeProgramModel()` (what `startWorkout`
    /// builds a session from) have to agree on which programme is active. `programs()` never ran
    /// the deload-expiry check, so an expired shim was still listed as the active programme — in
    /// its week 2 — while `startWorkout` had already handed control back to the interrupted one.
    @Test("Programmes shows the resumed programme as active once the deload week has expired")
    func programsAgreesWithTheSessionPathAboutTheActiveProgramme() throws {
        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = try #require(store.createProgram(from: .pushPullLegs))
        store.startProgram(id: original.id)
        store.planDeloadWeek()
        let deload = try #require(store.activeProgramModel())
        deload.startedAt = Calendar.current.date(byAdding: .day, value: -8, to: Date())
        store.save()

        // Read the Programmes screen *first*, with nothing else having touched the store.
        let listed = store.programs()
        #expect(listed.first { $0.isActive }?.id == original.id)
        #expect(listed.first { $0.name == "Deload Week" }?.isActive == false)
        // And the deload it actually took is kept, not pruned as an abandoned shim.
        #expect(listed.contains { $0.name == "Deload Week" && $0.completedAt != nil })
    }

    /// The previous-program pointer used to live in `UserDefaults.standard`, so a second device
    /// — which shares the SwiftData store through CloudKit but not the defaults — never resumed
    /// anything. It is derived from the programs themselves now.
    @Test("resuming works with no UserDefaults pointer at all")
    func resumesWithoutUserDefaults() throws {
        let store = try makeStore(seed: .exercises)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        let original = try #require(store.createProgram(from: .pushPullLegs))
        store.startProgram(id: original.id, now: Self.date(2026, 9, 7))
        store.planDeloadWeek()
        let active = try #require(store.activeProgramModel())
        active.startedAt = Self.date(2026, 9, 21)
        store.save()
        // What the other device sees: the store, and nothing else.
        let resumed = try #require(
            store.activeProgramModel(now: Self.date(2026, 9, 28), calendar: Self.calendar())
        )
        #expect(resumed.id == original.id)
    }
}
