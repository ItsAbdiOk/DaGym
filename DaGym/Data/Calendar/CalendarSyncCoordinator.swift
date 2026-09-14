import Foundation
import GymCore

/// The outcome the UI reads back — `CalendarSyncCoordinator` keeps one instance for the process.
/// `@Observable` so the Settings calendar row and the Schedule footnote re-render when a launch
/// or foreground sync (which no view awaits) finds the permission missing.
@MainActor
@Observable
final class CalendarSyncStatus {
    /// The most recent sync's result, or nil before the first one.
    private(set) var lastOutcome: CalendarSyncCoordinator.Outcome?

    /// What the calendar row / schedule footnote should say, or nil when all is well.
    var problemMessage: String? { lastOutcome?.problemMessage }

    fileprivate func record(_ outcome: CalendarSyncCoordinator.Outcome) {
        lastOutcome = outcome
    }
}

/// The one place a calendar sync is started from. Three things were wrong with syncing straight
/// from a view: it only ran from two settings screens (so the rolling 14-day window stopped
/// advancing 14 days after the last edit — `syncInBackground` now also runs on launch, on every
/// foreground and at midnight, via `RootView.refresh`); failures were swallowed by `try?` (so
/// denied access left the toggle on and the footnote still claiming "Synced" — an `Outcome`
/// comes back instead, and a refusal behind a user action turns `calendarSyncEnabled` back
/// off); and each screen kept its own serialising `Task` chain, so two screens could still sync
/// concurrently over the same event ids and duplicate a week. The chain is process-wide now.
///
/// Only a `.userAction` sync may put the permission sheet up. A `.background` one runs only when
/// Full Access is already granted; otherwise it leaves the preference alone and records
/// `.unauthorized` on `status` for the calendar row to show. Before that split, a lifter who had
/// granted "Add Events Only" on an older build got the Full Access sheet over Home on their
/// first launch after updating — and tapping "Don't Allow" switched the toggle off with no
/// message anywhere.
@MainActor
enum CalendarSyncCoordinator {
    enum Outcome: Equatable {
        /// `Preferences.calendarSyncEnabled` is off — nothing was attempted.
        case disabled
        case synced(events: Int)
        /// Access was refused behind an explicit action, or only "Add Events Only" was granted
        /// (which cannot be synced correctly — see `EventStoring`). `calendarSyncEnabled` has
        /// been turned back off.
        case denied(CalendarSyncError)
        /// A background sync found Full Access missing. Nothing was prompted and the
        /// preference is untouched: the user turned sync on, so it stays on and says why it
        /// can't run until they fix the permission or turn it off themselves.
        case unauthorized(CalendarSyncError)
        case failed(String)

        /// What the Schedule screen's footnote should say, or nil when there is nothing to say.
        var problemMessage: String? {
            switch self {
            case .disabled, .synced: nil
            case .denied(.accessDenied):
                "Calendar sync is off: DaGym doesn't have access to your calendars. "
                    + "Allow Full Access in Settings → Privacy → Calendars."
            case .denied(.writeOnlyAccess):
                "Calendar sync is off: \"Add Events Only\" isn't enough to keep your sessions "
                    + "up to date. Allow Full Access in Settings → Privacy → Calendars."
            case .unauthorized:
                "Calendar sync is paused: DaGym needs Full Access to your calendars. "
                    + "Allow it in Settings → Privacy → Calendars, or turn sync off."
            case .failed(let message): "Couldn't update your \"DaGym\" calendar: \(message)"
            }
        }
    }

    /// Who started the sync, which decides whether the permission sheet may appear.
    enum Trigger {
        /// The Settings toggle or a Schedule edit: the user is looking at the reason for a
        /// prompt, so `requestAccess()` may put one up. A refusal turns the preference off.
        case userAction
        /// Launch, foreground, midnight, History: nothing on screen explains a sheet, so this
        /// only runs when Full Access is already granted.
        case background
    }

    /// Read by the Settings calendar row and the Schedule footnote. Injectable per call so tests
    /// don't share it across parallel suites.
    static let status = CalendarSyncStatus()

    /// Serialises every sync in the process: two overlapping runs would read the same
    /// `existingEventIDs` and each create its own copy of the week.
    private static var chain: Task<Void, Never> = Task {}

    @discardableResult
    static func sync(
        store: WorkoutStore, preferences: Preferences, eventStore: EventStoring = EventKitStore(),
        now: Date = Date(), calendar: Calendar = .current, trigger: Trigger = .userAction,
        status: CalendarSyncStatus = Self.status
    ) async -> Outcome {
        guard preferences.calendarSyncEnabled else {
            status.record(.disabled)
            return .disabled
        }
        let previous = chain
        let task = Task { @MainActor () -> Outcome in
            await previous.value
            // Built only once the previous sync has saved its ids, so this one reads them.
            let request = ScheduleSyncRequest(
                schedule: store.schedule(), routines: store.routines(), startDate: now,
                defaultStartHour: preferences.scheduledStartHour,
                existingEventIDs: store.scheduleEventIDs(), calendar: calendar
            )
            let outcome = await run(
                request, store: store, preferences: preferences,
                service: CalendarSyncService(eventStore: eventStore), trigger: trigger
            )
            status.record(outcome)
            return outcome
        }
        chain = Task { _ = await task.value }
        return await task.value
    }

    /// Fire-and-forget entry point for the places that can't await (a `View` body's lifecycle
    /// hooks). Always `.background`: never prompts. Inert in a test process, like
    /// `WidgetSnapshotWriter.live` and `ResetSideEffects.live`: a unit or UI test must never
    /// touch the developer's real calendar or trigger a permission prompt.
    static func syncInBackground(store: WorkoutStore, preferences: Preferences) {
        guard !LaunchFlags.isTesting, preferences.calendarSyncEnabled else { return }
        Task { await sync(store: store, preferences: preferences, trigger: .background) }
    }

    /// `sending`: the request holds a non-`Sendable` closure and crosses into the
    /// nonisolated `CalendarSyncService`; it is freshly built by the caller and never reused.
    private static func run(
        _ request: sending ScheduleSyncRequest, store: WorkoutStore, preferences: Preferences,
        service: CalendarSyncService, trigger: Trigger
    ) async -> Outcome {
        do {
            let updated = try await service.sync(request, promptForAccess: trigger == .userAction)
            store.saveScheduleEventIDs(updated)
            return .synced(events: updated.count)
        } catch let error as CalendarSyncError {
            switch trigger {
            case .userAction:
                preferences.calendarSyncEnabled = false
                return .denied(error)
            case .background:
                return .unauthorized(error)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
