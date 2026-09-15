import Foundation
import GymCore

/// The rest timer's state, split out of `WorkoutSession` so the once-a-second tick lives on its
/// own observable. A view that reads only the session's `exercises` never registers a dependency
/// on `remaining`, and the rest bar that reads only `remaining` never re-renders for a logged
/// set. `WorkoutSession` forwards its old `rest*` names here, so callers and the watch compile
/// unchanged; the session's own `startRest`/`tickRest`/`adjustRest`/`skipRest` still drive it.
@Observable
@MainActor
final class RestTimerState {
    /// When the current rest ends; nil when not resting. `remaining` is a cache of
    /// `endDate - now`, refreshed by `WorkoutSession.tickRest()` so views re-render once a second.
    var endDate: Date?
    var remaining: Int = 0
    var total: Int = 0
    /// "Next <exercise name>" / "Last set done" — set whenever the next step isn't a plain
    /// weight × reps set. When it *is*, `nextWeightKg`/`nextReps` carry the raw data and the
    /// view (which has unit `Preferences`) builds the "Next 82.5 × 8" text.
    var nextLabel: String = ""
    var nextWeightKg: Double?
    var nextReps: Int?
    var isResting: Bool { remaining > 0 }
    /// Notified on every tick with the new `remaining`, so UI-only concerns (rest sound, screen
    /// flash) can live outside this UI-free model. Set by `ActiveWorkoutView`.
    var onTick: ((Int) -> Void)?
    /// Notified on every rest-state change (start/adjust/skip/natural end), so the Live
    /// Activity + lock screen notification (`Features/LiveActivity`) can mirror it without this
    /// UI-free model knowing about ActivityKit. Set by `ActiveWorkoutView+LiveActivity.swift`.
    var onStateChange: ((RestState) -> Void)?
    /// Mirrors `Preferences.restHaptics`; set by `ActiveWorkoutView` so the 3-2-1 and end taps
    /// honour the Settings toggle. Defaults on, like the preference.
    var haptics = true
    /// Mirrors `Preferences.restPauseSeconds`: the short pause a rest-pause set starts instead
    /// of the exercise's full rest. Set by `ActiveWorkoutView`.
    var pauseSeconds = 20
    /// Mirrors `Preferences.defaultRestSeconds`: the fallback rest for an exercise that carries
    /// none of its own, and — at `0` — the master off switch for the rest timer. Set by
    /// `ActiveWorkoutView`; see `WorkoutSession.restSeconds(after:set:)`.
    var defaultSeconds = 150
    // What the current rest is for — the `RestState` snapshot's context.
    var exerciseName = ""
    var setNumber = 0
    var setCount = 0
    var routineGlyph: RoutineGlyphInfo?

    /// Snapshot for the Live Activity / notification hook — see `RestState`.
    func snapshot(workoutTitle: String, now: Date, isEnded: Bool, isSkipped: Bool) -> RestState {
        RestState(
            remaining: remaining, total: total,
            endDate: endDate ?? now, workoutTitle: workoutTitle, exerciseName: exerciseName,
            setNumber: setNumber, setCount: setCount, nextWeightKg: nextWeightKg,
            nextReps: nextReps, fallbackNextLabel: nextLabel, isEnded: isEnded, isSkipped: isSkipped,
            routineSymbolName: routineGlyph?.symbolName ?? "dumbbell",
            routineTint: routineGlyph?.tint ?? "coral"
        )
    }
}

// MARK: - WorkoutSession forwarding

/// The session's pre-split rest API, forwarded to `rest`. Kept so `ActiveWorkoutView`, the Live
/// Activity controller and the watch read and write exactly the names they always did.
extension WorkoutSession {
    var restEndDate: Date? {
        get { rest.endDate }
        set { rest.endDate = newValue }
    }
    var restRemaining: Int {
        get { rest.remaining }
        set { rest.remaining = newValue }
    }
    var restTotal: Int {
        get { rest.total }
        set { rest.total = newValue }
    }
    var restNextLabel: String {
        get { rest.nextLabel }
        set { rest.nextLabel = newValue }
    }
    var restNextWeightKg: Double? {
        get { rest.nextWeightKg }
        set { rest.nextWeightKg = newValue }
    }
    var restNextReps: Int? {
        get { rest.nextReps }
        set { rest.nextReps = newValue }
    }
    var isResting: Bool { rest.isResting }
    var onRestTick: ((Int) -> Void)? {
        get { rest.onTick }
        set { rest.onTick = newValue }
    }
    var onRestStateChange: ((RestState) -> Void)? {
        get { rest.onStateChange }
        set { rest.onStateChange = newValue }
    }
    var restHaptics: Bool {
        get { rest.haptics }
        set { rest.haptics = newValue }
    }
    var restPauseSeconds: Int {
        get { rest.pauseSeconds }
        set { rest.pauseSeconds = newValue }
    }
    var defaultRestSeconds: Int {
        get { rest.defaultSeconds }
        set { rest.defaultSeconds = newValue }
    }
}
