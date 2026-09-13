import ActivityKit
import SwiftUI
import WidgetKit

/// The rest-timer Live Activity: Lock Screen banner + all four Dynamic Island presentations.
/// Layouts live in `RestLockScreenView.swift` / `RestDynamicIsland.swift`; this file only wires
/// `ActivityConfiguration`. See mockup 03b (scratchpad/mock/03_01.png).
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(WidgetPalette.background)
                .activitySystemActionForegroundColor(WidgetPalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RestDynamicIsland.expandedLeading(context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestDynamicIsland.expandedTrailing(context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestDynamicIsland.expandedBottom(context.state)
                }
            } compactLeading: {
                RestDynamicIsland.compactLeading()
            } compactTrailing: {
                RestDynamicIsland.compactTrailing(context.state)
            } minimal: {
                RestDynamicIsland.minimal(context.state)
            }
            .keylineTint(WidgetPalette.coral)
        }
    }
}
