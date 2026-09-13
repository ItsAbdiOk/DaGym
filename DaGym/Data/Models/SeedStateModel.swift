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
        let descriptor = FetchDescriptor<SeedStateModel>(sortBy: [SortDescriptor(\.updatedAt)])
        let rows = (try? context.fetch(descriptor)) ?? []
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

    /// Re-runs `dedupeSeededRows()` after each batch of remote (CloudKit) changes lands, coalesced
    /// to one pass per second so a large first import doesn't trigger a pass per transaction.
    /// The caller keeps the returned observer alive for as long as it wants the passes to run.
    func startRemoteChangeDedupe(center: NotificationCenter = .default) -> RemoteChangeDeduper {
        RemoteChangeDeduper(store: self, center: center)
    }
}

/// Owns the `NSPersistentStoreRemoteChange` subscription for `WorkoutStore.dedupeSeededRows()`.
@MainActor
final class RemoteChangeDeduper {
    private let center: NotificationCenter
    private var token: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?

    init(store: WorkoutStore, center: NotificationCenter) {
        self.center = center
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
        guard pending == nil else { return }
        pending = Task { [weak self, weak store] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let store, !Task.isCancelled else { return }
            self.pending = nil
            store.dedupeSeededRows()
        }
    }
}
