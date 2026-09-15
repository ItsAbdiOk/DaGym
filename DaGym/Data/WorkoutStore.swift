import Foundation
import GymCore
import SwiftData
import os

let storeLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "store")
/// Intervals on the store's hot paths (`sync`, `finish`, `history`, `exerciseCatalogue`), for
/// Instruments' os_signpost track. Same subsystem/category as `LaunchTiming`.
let storeSignposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

/// Returned by `WorkoutStore.finish(session:)`.
struct WorkoutSummary {
    var durationSeconds: Int
    var volumeKg: Double
    var setsDone: Int
    var prs: [PersonalRecordInfo]
    var musclesHit: [Muscle: Double]
    /// Milestone tiers newly earned by this workout (plan.md §6.4), empty most of the time.
    var achievements: [AchievementInfo] = []
    /// The previous finished workout on the same routine (same title when there's no routine)
    /// dated before this one — the "vs last time" line. Nil the first time a routine is run.
    var previous: PreviousWorkoutSummary?
    /// Best e1RM this session vs the previous one, per exercise this session trained.
    var e1rmChanges: [ExerciseE1RMChange] = []
    /// Σ metres over completed cardio sets — shown beside the volume when non-zero.
    var distanceMeters: Double = 0
    /// The pre-summarised facts the coach debrief reads (`WorkoutStore+CoachFacts.swift`). Nil
    /// for a summary built without a session (a re-finish, the debug screen) — no card then.
    var debriefFacts: SessionSummaryFacts?
}

/// The headline numbers of the workout `WorkoutSummary.previous` compares against.
struct PreviousWorkoutSummary: Hashable {
    var workoutID: UUID
    var date: Date
    var volumeKg: Double
    var setsDone: Int
    var durationSeconds: Int
    var prCount: Int
}

/// One exercise's best e1RM then vs now; either side is nil when that session had no
/// completed working set with a load and reps.
struct ExerciseE1RMChange: Hashable, Identifiable {
    var exerciseID: UUID
    var name: String
    var previous: Double?
    var current: Double?
    var id: UUID { exerciseID }
}

/// The single source of truth for exercises, routines and workouts. Wraps a
/// `ModelContext` and converts to/from the plain UI value types in
/// `DaGym/SampleData/Models.swift`. See `WorkoutStore+Exercises.swift`,
/// `WorkoutStore+Workouts.swift`, `WorkoutStore+History.swift` and
/// `WorkoutStore+Routines.swift` for the rest of the public API.
@MainActor
@Observable
final class WorkoutStore {
    let context: ModelContext
    /// Notified with the freshly-ended `WorkoutModel` at the end of `finish(session:)`. Set by
    /// `HealthSyncService.bind(to:)` to write the session to Apple Health — this type stays
    /// unaware of HealthKit itself (plan.md §6.8).
    var onWorkoutFinished: ((WorkoutModel) -> Void)?
    /// A second, additive hook list for the same "workout just finished" moment — used by
    /// `TrainingNotificationScheduler` to reschedule the streak/recap notifications without
    /// touching `onWorkoutFinished`, which `HealthSyncService` already owns.
    var workoutFinishedObservers: [(WorkoutModel) -> Void] = []

    /// Progress photos live in their own local-only container (see `ModelContainer.dagymPhotos`).
    /// `nil` when that container failed to open: photo features then read as empty and refuse
    /// writes, rather than inserting `ProgressPhotoModel` into the main context (whose schema
    /// doesn't contain it — a trap, not an error).
    let photoContext: ModelContext?

    /// HealthKit-derived rows (imported external workouts, delete tombstones) live in their own
    /// always-local container (see `ModelContainer.dagymHealth`) — App Store Guideline 5.1.3
    /// forbids storing HealthKit data in iCloud, and the main store is CloudKit-mirrored whenever
    /// `Preferences.iCloudSyncEnabled` is on. `nil` when that container failed to open: Health
    /// import then reads as empty and refuses writes.
    let healthContext: ModelContext?

    /// Called with a `WorkoutModel.healthKitID` when a workout DaGym itself wrote to Apple Health
    /// is deleted here, so `HealthSyncService` can delete the `HKWorkout` it saved. Set by
    /// `HealthSyncService.bind(to:)`; this type stays unaware of HealthKit itself.
    var onWorkoutDeletedFromHealth: ((String) -> Void)?

    /// Bumps on every successful `save()`/`savePhotos()` — the one signal screens key their
    /// `refresh()` on (`.onChange(of: store.changeToken)`) so a finished workout, a schedule
    /// edit or a photo delete shows up without a tab switch. Never decrements.
    private(set) var changeToken = 0
    /// Bumps on every `saveSession()` — the per-set `sync(session:)` save — instead of
    /// `changeToken`, so a logged set redraws the active workout without also re-running every
    /// `changeToken`-keyed `refresh()` (Home, History, Library) on each tick of the session.
    private(set) var sessionToken = 0

    // Not `private(set)`: the writers are the `fetch`/`fetchFirst`/`fetchCount` helpers below
    // *and* nothing else — a private setter would be file-scoped and every store extension
    // lives in its own file.
    /// Test-only instrumentation: bumped once per SwiftData round trip against the main
    /// `context` — every store read goes through `fetch(_:)`, `fetchFirst(_:)` or
    /// `fetchCount(_:)` so this is the real query count, not one hand-picked helper's.
    /// `WorkoutStoreStartPerformanceTests` asserts a 2-exercise and a 12-exercise routine issue
    /// the *same* number of queries, which is what makes an N+1 impossible to reintroduce.
    /// `@ObservationIgnored` is load-bearing: `fetch` bumps this counter, and a view that reads
    /// the store from `body` (`PlateChip` → `activeInventory()`) would otherwise register a
    /// dependency on it *and* write it in the same pass — an invalidation loop that pinned the
    /// Active Workout screen at 100% CPU and never drew a frame.
    @ObservationIgnored var queryCount = 0

    /// The live library, read once and reused until the next `save()` (see
    /// `exerciseCatalogue()`). Ignored by observation for the same reason `queryCount` is: it is
    /// filled from inside a view's `body`.
    @ObservationIgnored var cachedCatalogue: (token: Int, catalogue: ExerciseCatalogue)?

    /// Where the store reads the lifter's units from when a caller doesn't pass one. Defaults to
    /// the same `UserDefaults.standard` keys `Preferences` writes; `DaGymApp` may hand in the
    /// live `Preferences` instead so the two can never disagree. See `WorkoutStore+Units.swift`.
    @ObservationIgnored var units: StoreUnitProvider

    /// The one place the main context is read. Every `WorkoutStore+*` extension calls these
    /// rather than `context.fetch` directly, so `queryCount` can't drift out of date. A failed
    /// fetch reads as empty — but is logged, so a predicate SwiftData can't translate (the
    /// `mergedIntoID == nil` case) shows up in Console instead of as a silently empty screen.
    func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        queryCount += 1
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logFetchFailure(Model.self, error)
            return []
        }
    }

    func fetchFirst<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> Model? {
        queryCount += 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            Self.logFetchFailure(Model.self, error)
            return nil
        }
    }

    func fetchCount<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> Int {
        queryCount += 1
        do {
            return try context.fetchCount(descriptor)
        } catch {
            Self.logFetchFailure(Model.self, error)
            return 0
        }
    }

    private static func logFetchFailure<Model: PersistentModel>(_ type: Model.Type, _ error: any Error) {
        let name = String(describing: type)
        storeLogger.error(
            "Fetch of \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    init(
        context: ModelContext, photoContext: ModelContext?, healthContext: ModelContext? = nil,
        units: StoreUnitProvider = .userDefaults()
    ) {
        self.context = context
        self.photoContext = photoContext
        self.healthContext = healthContext
        self.units = units
    }

    /// Tests and previews: photos and Health imports in in-memory stores, no extra setup.
    convenience init(context: ModelContext) {
        let photos = (try? ModelContainer.dagymPhotos(inMemory: true)).map(ModelContext.init)
        let health = (try? ModelContainer.dagymHealth(inMemory: true)).map(ModelContext.init)
        self.init(context: context, photoContext: photos, healthContext: health)
    }

    func savePhotos() {
        guard let photoContext, photoContext.hasChanges else { return }
        do {
            try photoContext.save()
            changeToken += 1
        } catch {
            storeLogger.error("Photo store save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Persists the always-local Health store (imported workouts, tombstones) and bumps
    /// `changeToken` so History redraws, exactly as `savePhotos()` does for the photo store.
    func saveHealth() {
        guard let healthContext, healthContext.hasChanges else { return }
        do {
            try healthContext.save()
            changeToken += 1
        } catch {
            storeLogger.error("Health store save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
            changeToken += 1
        } catch {
            storeLogger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `save()` for the in-progress session's own writes (`sync(session:)`): bumps
    /// `sessionToken`, not `changeToken` — a set logged mid-workout is not a change the other
    /// tabs need to refresh for. `finish` still ends in a normal `save()`.
    func saveSession() {
        guard context.hasChanges else { return }
        do {
            try context.save()
            sessionToken += 1
        } catch {
            storeLogger.error("Session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// For a caller that saved `context` itself (backup import writes through the context
    /// directly): bumps `changeToken` so the token-keyed screens redraw, exactly as `save()`
    /// would have.
    func noteExternalSave() {
        changeToken += 1
    }

    /// `mergedIntoID == nil` throughout: a row that lost a seed fold is a tombstone kept only
    /// so late-arriving CloudKit children still resolve (`ExerciseSeeder.dedupe`), and must
    /// never be handed to a caller as if it were a real library exercise.
    func fetchExerciseModel(id: UUID) -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetchFirst(descriptor).flatMap { $0.mergedIntoID == nil ? $0 : nil }
    }

    /// Every library exercise in `ids`, keyed by id, in one query — the batched form of
    /// `fetchExerciseModel(id:)` for callers that would otherwise loop over it once per
    /// exercise in a routine.
    func fetchExerciseModels(ids: Set<UUID>) -> [UUID: ExerciseModel] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(ids)
        let descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { wanted.contains($0.id) })
        let live = fetch(descriptor).filter { $0.mergedIntoID == nil }
        return Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func fetchWorkoutModel(id: UUID) -> WorkoutModel? {
        var descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetchFirst(descriptor)
    }

    /// Every live routine in `ids`, keyed by id, in one query — the batched form of
    /// `fetchRoutineModel(id:)`.
    func fetchRoutineModels(ids: Set<UUID>) -> [UUID: RoutineModel] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(ids)
        let descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { wanted.contains($0.id) })
        let live = fetch(descriptor).filter { $0.mergedIntoID == nil }
        return Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func fetchRoutineModel(id: UUID) -> RoutineModel? {
        var descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetchFirst(descriptor).flatMap { $0.mergedIntoID == nil ? $0 : nil }
    }
}
