import Foundation

/// The shell's view of the workout in progress: which session is alive, and whether its
/// full-screen cover is up or minimised to the resume bar above the tab bar. Kept as a value
/// so `RootView` has one place to ask "is there a workout?" (`session`) and "is it on screen?"
/// (`presented`), and so the minimise / resume / finish transitions can be pinned by a test
/// without a view. A minimised session is still the live `WorkoutSession` — its rest timer and
/// Live Activity carry on — only the cover has gone.
struct WorkoutPresentation {
    private(set) var session: WorkoutSession?
    private(set) var isMinimised = false

    /// What the cover binds to: the session while it is up, nil while minimised or absent.
    var presented: WorkoutSession? { isMinimised ? nil : session }

    /// A session exists but its cover is down — the resume bar's condition.
    var showsResumeBar: Bool { session != nil && isMinimised }

    /// A new session is always presented; starting one over a minimised session replaces it,
    /// so callers check `session` first (`RootView.resumeIfActive`).
    mutating func present(_ session: WorkoutSession) {
        self.session = session
        isMinimised = false
    }

    /// Drops the cover and keeps the session. Nothing to minimise is a no-op.
    mutating func minimise() {
        guard session != nil else { return }
        isMinimised = true
    }

    /// Puts the cover back over the same session. Without one it is a no-op.
    mutating func resume() {
        guard session != nil else { return }
        isMinimised = false
    }

    /// The session is over (finished or discarded): clears both, returning what was cleared so
    /// the caller can title the summary.
    @discardableResult
    mutating func finish() -> WorkoutSession? {
        defer {
            session = nil
            isMinimised = false
        }
        return session
    }
}
