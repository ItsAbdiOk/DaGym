import SwiftUI
import WidgetKit

/// Dynamic Island presentations for the rest timer: compact leading = routine glyph, compact
/// trailing = countdown; minimal = ring only; expanded = ring + countdown + next-set label +
/// buttons.
///
/// The resolved `WidgetPalette` is passed in rather than read from `@Environment`: these are
/// static functions with no view of their own to hang an environment property on. The nested
/// views that *are* views (`RestRing`, `RestButtonRow`, the glyph) still read it from the
/// environment `RestLiveActivity` sets on each region.
enum RestDynamicIsland {
    static func expandedLeading(_ state: RestActivityAttributes.ContentState) -> some View {
        RestRing(state: state).frame(width: 34, height: 34)
    }

    static func expandedTrailing(
        _ state: RestActivityAttributes.ContentState, palette: WidgetPalette
    ) -> some View {
        Text(timerInterval: state.startDate...state.endDate, countsDown: true)
            .font(WidgetFont.condensed(size: 24))
            .foregroundStyle(palette.ink)
    }

    static func expandedBottom(
        _ state: RestActivityAttributes.ContentState, palette: WidgetPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(state.setLabel) · Next: \(state.nextSetLabel)")
                .font(.footnote)
                .foregroundStyle(palette.inkMuted)
                .lineLimit(1)
            RestButtonRow()
        }
    }

    static func compactLeading(_ attributes: RestActivityAttributes) -> some View {
        RoutineWidgetGlyph(symbolName: attributes.routineSymbolName, tint: attributes.routineTint, size: 20)
    }

    static func compactTrailing(
        _ state: RestActivityAttributes.ContentState, palette: WidgetPalette
    ) -> some View {
        Text(timerInterval: state.startDate...state.endDate, countsDown: true)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(palette.ink)
    }

    static func minimal(_ state: RestActivityAttributes.ContentState) -> some View {
        RestRing(state: state)
    }
}
