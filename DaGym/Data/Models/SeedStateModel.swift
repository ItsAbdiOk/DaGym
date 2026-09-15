import CoreData
import Foundation
import SwiftData

/// The one row that records what the seeders have already applied to *this* store — the
/// exercise seed version and whether the starter routines/equipment profiles were written.
/// Living in the store (rather than `UserDefaults`) means an in-memory fallback launch, a UI test
/// run, or a second iCloud device can never stamp a version the on-disk rows never received.
/// CloudKit can merge two of these; `WorkoutStore.dedupeSeededRows()` folds them into one.
@Model
final class SeedStateModel {
    var id: UUID = UUID()
    var exerciseSeedVersion: Int = 0
    var routinesSeeded: Bool = false
    var equipmentSeeded: Bool = false
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(), exerciseSeedVersion: Int = 0, routinesSeeded: Bool = false,
        equipmentSeeded: Bool = false, updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseSeedVersion = exerciseSeedVersion
        self.routinesSeeded = routinesSeeded
        self.equipmentSeeded = equipmentSeeded
        self.updatedAt = updatedAt
    }
}

@MainActor
enum SeedState {
    /// The store's seed-state row, creating it on first use. When CloudKit has merged several,
    /// the strongest values win (highest version, any `true`) and the extras are removed.
    static func row(in context: ModelContext) -> SeedStateModel {
        let descriptor = FetchDescriptor<SeedStateModel>()
        // Sorted in memory, not by the fetch: `updatedAt` alone is not a total order — two
        // devices that seeded in the same second kept *different* rows and each deleted the
        // other's, which bounced `routinesSeeded` back to false and re-seeded all 13 starters
        // into a store whose owner had deliberately deleted every routine. `id` breaks the tie
        // so every device converges on the same survivor.
        let rows = ((try? context.fetch(descriptor)) ?? []).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let survivor = rows.first else {
            let created = SeedStateModel()
            context.insert(created)
            return created
        }
        for extra in rows.dropFirst() {
            survivor.exerciseSeedVersion = max(survivor.exerciseSeedVersion, extra.exerciseSeedVersion)
            survivor.routinesSeeded = survivor.routinesSeeded || extra.routinesSeeded
            survivor.equipmentSeeded = survivor.equipmentSeeded || extra.equipmentSeeded
            context.delete(extra)
        }
        return survivor
    }
}

extension WorkoutStore {
    /// Collapses every duplicate a CloudKit merge can produce when two devices each seeded
    /// before the other's rows arrived: exercises by `seedID`, routines by `importedFromID`,
    /// identical equipment profiles, schedule rows, and the seed-state row itself. Relationships
    /// and id references are re-pointed at the survivor, and the PR cache is rebuilt when any
    /// exercise was folded. Runs at the end of seeding on every launch and after each remote
    /// import; a no-op when there is nothing to fold.
    @discardableResult
    func dedupeSeededRows() -> Int {
        _ = SeedState.row(in: context)
        let foldedExercises = ExerciseSeeder.dedupe(in: context)
        let foldedRoutines = dedupeRoutines()
        let foldedProfiles = dedupeEquipmentProfiles()
        let foldedSchedules = dedupeScheduleRows()
        let folded = foldedExercises + foldedRoutines + foldedProfiles + foldedSchedules
        if foldedExercises > 0 { rebuildPersonalRecords() }
        if folded > 0 || context.hasChanges { save() }
        return folded
    }

    /// Re-runs `dedupeSeededRows()` after remote (CloudKit) changes land, once the stream has
    /// been quiet for `RemoteChangeDeduper.quietPeriod` (and at least every `maxDelay` while it
    /// never is). The caller keeps the returned observer alive for as long as it wants the
    /// passes to run.
    func startRemoteChangeDedupe(
        center: NotificationCenter = .default, quietPeriod: Duration = RemoteChangeDeduper.quietPeriod,
        maxDelay: Duration = RemoteChangeDeduper.maxDelay
    ) -> RemoteChangeDeduper {
        RemoteChangeDeduper(store: self, center: center, quietPeriod: quietPeriod, maxDelay: maxDelay)
    }
}

/// Owns the `NSPersistentStoreRemoteChange` subscription for `WorkoutStore.dedupeSeededRows()`.
///
/// A pass reads every exercise row (~100 ms on the main thread with a full catalogue, measured
/// on an iPhone 16 Pro), and CloudKit posts a remote change per mirroring transaction — dozens
/// a minute while it exports or imports. The old one-second coalescing therefore ran a pass
/// nearly every second for the whole sync, a visible hitch on every screen. Now a pass waits
/// for the stream to go quiet, with a ceiling so a long import still gets folded partway.
@MainActor
final class RemoteChangeDeduper {
    static let quietPeriod: Duration = .seconds(3)
    static let maxDelay: Duration = .seconds(30)

    private let center: NotificationCenter
    private let quietPeriod: Duration
    private let maxDelay: Duration
    private var token: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?
    /// When the oldest not-yet-folded change arrived, so a continuous stream can't starve the pass.
    private var firstPendingChange: ContinuousClock.Instant?
    /// Passes run so far — for tests, which count them rather than wait on wall-clock.
    private(set) var passCount = 0

    init(
        store: WorkoutStore, center: NotificationCenter,
        quietPeriod: Duration = RemoteChangeDeduper.quietPeriod,
        maxDelay: Duration = RemoteChangeDeduper.maxDelay
    ) {
        self.center = center
        self.quietPeriod = quietPeriod
        self.maxDelay = maxDelay
        token = center.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self, weak store] _ in
            MainActor.assumeIsolated {
                guard let self, let store else { return }
                self.schedule(store: store)
            }
        }
    }

    isolated deinit {
        if let token { center.removeObserver(token) }
        pending?.cancel()
    }

    private func schedule(store: WorkoutStore) {
        let now = ContinuousClock.now
        let first = firstPendingChange ?? now
        firstPendingChange = first
        // Trailing-edge debounce: every new change pushes the pass back by `quietPeriod`,
        // but never past `first + maxDelay`.
        let delay = min(quietPeriod, max(.zero, (first + maxDelay) - now))
        pending?.cancel()
        pending = Task { [weak self, weak store] in
            try? await Task.sleep(for: delay)
            guard let self, let store, !Task.isCancelled else { return }
            self.pending = nil
            self.firstPendingChange = nil
            self.passCount += 1
            store.dedupeSeededRows()
        }
    }
}
