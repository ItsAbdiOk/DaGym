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
        activity = (try? Activity.request(attributes: attributes, content: Self.content(state)))
            .map(ActivityHandle.init)
    }

    func update(state: RestActivityAttributes.ContentState) {
        guard let handle = activity else { return }
        let content = Self.content(state)
        Task { await handle.activity.update(content) }
    }

    /// A `staleDate` shortly after the rest ends. Without one the banner claims to be live
    /// forever: if the app is jetsammed mid-rest, nothing is left to end the activity, and the
    /// countdown hits 0:00 and then just sits there looking current. With it, iOS dims the
    /// content and stops presenting it as live even though no process is around to say so.
    private static func content(
        _ state: RestActivityAttributes.ContentState
    ) -> ActivityContent<RestActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: state.endDate.addingTimeInterval(30))
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
