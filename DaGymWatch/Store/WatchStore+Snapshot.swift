import CoreData
import Foundation

extension WatchStore {
    /// Starts watching for CloudKit imports. Routines, the schedule and history all arrive by
    /// sync — on a fresh watch Home says "Routines sync from your iPhone." until they do, and
    /// without this it kept saying so until the next relaunch. Idle only: a live session's
    /// pages are built from the session, and its Home is rebuilt at finish anyway.
    func observeRemoteChanges(
        center: NotificationCenter = .default,
        quietPeriod: Duration = WatchRemoteChangeObserver.quietPeriod,
        maxDelay: Duration = WatchRemoteChangeObserver.maxDelay
    ) {
        remoteChanges = WatchRemoteChangeObserver(
            center: center, quietPeriod: quietPeriod, maxDelay: maxDelay
        ) { [weak self] in
            guard let self, self.session == nil else { return }
            self.refreshHome()
        }
    }
}

/// Owns the `NSPersistentStoreRemoteChange` subscription for the watch — the same trailing-edge
/// debounce as the phone's `RemoteChangeDeduper` (`DaGym/Data/Models/SeedStateModel.swift`):
/// CloudKit posts a change per mirroring transaction, dozens a minute during an import, and a
/// Home rebuild per transaction would hitch every screen for the whole sync. A pass waits for
/// the stream to go quiet, with a ceiling so a long first sync still shows something partway.
@MainActor
final class WatchRemoteChangeObserver {
    static let quietPeriod: Duration = .seconds(2)
    static let maxDelay: Duration = .seconds(20)

    private let center: NotificationCenter
    private let quietPeriod: Duration
    private let maxDelay: Duration
    private let onChange: () -> Void
    private var token: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?
    /// When the oldest not-yet-handled change arrived, so a continuous stream can't starve the pass.
    private var firstPendingChange: ContinuousClock.Instant?
    /// Passes run so far — for tests, which count them rather than wait on wall-clock.
    private(set) var passCount = 0

    init(
        center: NotificationCenter, quietPeriod: Duration = WatchRemoteChangeObserver.quietPeriod,
        maxDelay: Duration = WatchRemoteChangeObserver.maxDelay, onChange: @escaping () -> Void
    ) {
        self.center = center
        self.quietPeriod = quietPeriod
        self.maxDelay = maxDelay
        self.onChange = onChange
        token = center.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }

    isolated deinit {
        if let token { center.removeObserver(token) }
        pending?.cancel()
    }

    private func schedule() {
        let now = ContinuousClock.now
        let first = firstPendingChange ?? now
        firstPendingChange = first
        // Trailing-edge debounce: every new change pushes the pass back by `quietPeriod`,
        // but never past `first + maxDelay`.
        let delay = min(quietPeriod, max(.zero, (first + maxDelay) - now))
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.firstPendingChange = nil
            self.passCount += 1
            self.onChange()
        }
    }
}
