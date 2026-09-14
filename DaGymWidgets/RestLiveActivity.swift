import ActivityKit
import SwiftUI
import WidgetKit

/// The rest-timer Live Activity: Lock Screen banner + all four Dynamic Island presentations.
/// Layouts live in `RestLockScreenView.swift` / `RestDynamicIsland.swift`; this file only wires
/// `ActivityConfiguration`. See mockup 03b (scratchpad/mock/03_01.png).
struct RestLiveActivity: Widget {
    /// The Lock Screen is rendered dark; the user's own light/dark choice only reaches us through
    /// `attributes.appearance`, so an explicit "Light" still themes the banner.
    private func palette(_ attributes: RestActivityAttributes) -> WidgetPalette {
        WidgetPalette(
            accent: attributes.accent ?? "coral", appearance: attributes.appearance ?? "dark",
            systemIsDark: true
        )
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            let palette = palette(context.attributes)
            RestLockScreenView(attributes: context.attributes, state: context.state)
                .environment(\.widgetPalette, palette)
                .activityBackgroundTint(palette.background)
                .activitySystemActionForegroundColor(palette.ink)
        } dynamicIsland: { context in
            let palette = palette(context.attributes)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RestDynamicIsland.expandedLeading(context.state).environment(\.widgetPalette, palette)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestDynamicIsland.expandedTrailing(context.state, palette: palette)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestDynamicIsland.expandedBottom(context.state, palette: palette)
                        .environment(\.widgetPalette, palette)
                }
            } compactLeading: {
                RestDynamicIsland.compactLeading(context.attributes).environment(\.widgetPalette, palette)
            } compactTrailing: {
                RestDynamicIsland.compactTrailing(context.state, palette: palette)
            } minimal: {
                RestDynamicIsland.minimal(context.state).environment(\.widgetPalette, palette)
            }
            .keylineTint(palette.accent)
        }
    }
}
