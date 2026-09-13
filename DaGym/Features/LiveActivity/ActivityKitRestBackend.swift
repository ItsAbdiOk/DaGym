import ActivityKit
import Foundation

/// The real `RestActivityBackend`: one `Activity<RestActivityAttributes>` at a time, with the
/// async ActivityKit calls kicked off in tasks so the controller stays synchronous.
@MainActor
final class ActivityKitRestBackend: RestActivityBackend {
    /// `Activity` is documented as safe to use from any context but is not marked Sendable;
    /// boxing it lets the async ActivityKit calls leave the main actor without a diagnostic.
    private final class ActivityHandle: @unchecked Sendable {
        let activity: Activity<RestActivityAttributes>
        init(_ activity: Activity<RestActivityAttributes>) { self.activity = activity }
    }

    private var activity: ActivityHandle?

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var hasActivity: Bool { activity != nil }

    func endStaleActivities() {
        let stale = Activity<RestActivityAttributes>.activities.map(ActivityHandle.init)
        guard !stale.isEmpty else { return }
        Task {
            for handle in stale {
                await handle.activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func start(attributes: RestActivityAttributes, state: RestActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: nil)
        activity = (try? Activity.request(attributes: attributes, content: content)).map(ActivityHandle.init)
    }

    func update(state: RestActivityAttributes.ContentState) {
        guard let handle = activity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await handle.activity.update(content) }
    }

    func end(_ dismissal: RestActivityDismissal) {
        guard let handle = activity else { return }
        activity = nil
        let policy: ActivityUIDismissalPolicy
        switch dismissal {
        case .immediate: policy = .immediate
        case .after(let date): policy = .after(date)
        }
        Task { await handle.activity.end(handle.activity.content, dismissalPolicy: policy) }
    }
}
