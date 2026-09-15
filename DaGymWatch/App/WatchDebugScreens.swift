import Foundation
import GymCore

#if DEBUG
/// `-dgWatchScreen <name>` — jumps the sample store into a screen state so the simulator can be
/// screenshotted without driving the UI. See `WatchLaunchFlags` for the names.
@MainActor
enum WatchDebugScreens {
    static func apply(_ name: String?, store: WatchStore, isSample: Bool = WatchLaunchFlags.isSample) {
        guard let name, isSample else { return }
        switch name {
        case "home":
            break
        case "home-rest":
            // Today off the schedule, the other days kept, so Home shows the routine list.
            var schedule = store.store.schedule()
            let today = Weekday(rawValue: Calendar.current.component(.weekday, from: Date())) ?? .monday
            schedule.setRoutines([], on: today)
            store.store.saveSchedule(schedule)
            store.refreshHome()
        case "settings":
            store.debugOpensSettings = true
        case "complications":
            store.debugComplicationsPage = 0
        case _ where name.hasPrefix("complications-"):
            store.debugComplicationsPage = Int(name.dropFirst("complications-".count)) ?? 0
        case "voice":
            openVoice(store: store)
        default:
            applyWorkoutState(name, store: store)
        }
    }

    private static func applyWorkoutState(_ name: String, store: WatchStore) {
        switch name {
        case "summary":
            // A finished session, not a token one: every bench row (the store ramps five
            // warm-ups in front of the four working sets), started 38 minutes ago so the clock
            // and the set count on screen 6 are the real thing.
            startBench(store: store)
            backdateStart(store: store, minutes: 38)
            logWarmups(store: store)
            logBenchSets(store: store, count: 4)
            store.finish()
        case "working":
            startBench(store: store)
            logWarmups(store: store)
        case "amrap":
            startBench(store: store)
            logWarmups(store: store)
            logBenchSets(store: store, count: 3)
            store.updateSet(exerciseID: benchID(store)) { $0.reps = 7 }
        case "pr":
            startBench(store: store)
            logWarmups(store: store)
            store.holdsRecordCard = true
            store.updateSet(exerciseID: benchID(store)) { $0.weightKg = 100; $0.reps = 6 }
            store.logCurrentSet(exerciseID: benchID(store))
        case "rest":
            startBench(store: store)
            store.updateSet(exerciseID: benchID(store)) { $0.weightKg = 60 }
            store.logCurrentSet(exerciseID: benchID(store))
            store.scrubRest(to: 40)
            store.session?.restTotal = 40
        case "rest-full":
            startBench(store: store)
            logWarmups(store: store)
            store.logCurrentSet(exerciseID: benchID(store))
            store.recordCard = nil
            store.scrubRest(to: 92)
        case "rest-final":
            startBench(store: store)
            logWarmups(store: store)
            store.logCurrentSet(exerciseID: benchID(store))
            store.recordCard = nil
            store.scrubRest(to: 7)
        default:
            startBench(store: store)
            if name.hasPrefix("active-"), let page = Int(name.dropFirst("active-".count)) {
                store.pageIndex = page
            }
        }
    }

    private static func openVoice(store: WatchStore) {
        startBench(store: store)
        logBenchSets(store: store, count: 2)
        store.skipRest()
        store.debugVoiceParse = WatchVoiceParse(
            phrase: "same again but 7 reps, felt like an eight", exerciseID: benchID(store),
            exerciseName: "Bench Press", setNumber: 3, weightKg: 100, reps: 7, effort: Effort(rpe: 8)
        )
        store.debugShowVoice = true
    }

    private static func startBench(store: WatchStore) {
        guard store.session == nil, let routine = store.home.todaysRoutine else { return }
        store.start(routineID: routine.id)
        store.session?.defaultRestSeconds = 150
    }

    /// Moves the session's start (and its persisted workout's) into the past so the summary's
    /// duration is what a real session would show.
    private static func backdateStart(store: WatchStore, minutes: Int) {
        guard let session = store.session else { return }
        let startedAt = Date().addingTimeInterval(-Double(minutes) * 60)
        session.startedAt = startedAt
        if let workoutID = session.workoutID, let model = store.store.workout(id: workoutID) {
            model.startedAt = startedAt
        }
    }

    /// Logs every warm-up row of the bench so the working set (2A) is on deck.
    private static func logWarmups(store: WatchStore) {
        while let entry = store.session?.exercises.first,
              entry.sets.first(where: { !$0.isDone })?.kind == .warmup {
            store.logCurrentSet(exerciseID: entry.id)
            store.skipRest()
        }
    }

    private static func benchID(_ store: WatchStore) -> UUID {
        store.session?.exercises.first?.id ?? UUID()
    }

    /// Logs the first `count` bench rows (two warm-ups, then working sets) and skips each rest.
    private static func logBenchSets(store: WatchStore, count: Int) {
        for _ in 0..<count {
            store.logCurrentSet(exerciseID: benchID(store))
            store.recordCard = nil
            store.skipRest()
        }
    }
}
#endif
