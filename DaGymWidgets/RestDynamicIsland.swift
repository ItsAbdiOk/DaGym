import SwiftUI
import WidgetKit

/// Dynamic Island presentations for the rest timer: compact leading = routine glyph, compact
/// trailing = countdown; minimal = ring only; expanded = ring + countdown + next-set label +
/// buttons.
enum RestDynamicIsland {
    static func expandedLeading(_ state: RestActivityAttributes.ContentState) -> some View {
        RestRing(state: state).frame(width: 34, height: 34)
    }

    static func expandedTrailing(_ state: RestActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startDate...state.endDate, countsDown: true)
            .font(WidgetFont.condensed(size: 24))
            .foregroundStyle(WidgetPalette.ink)
    }

    static func expandedBottom(_ state: RestActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(state.setLabel) · Next: \(state.nextSetLabel)")
                .font(.footnote)
                .foregroundStyle(WidgetPalette.inkMuted)
                .lineLimit(1)
            RestButtonRow()
        }
    }

    static func compactLeading(_ attributes: RestActivityAttributes) -> some View {
        RoutineWidgetGlyph(symbolName: attributes.routineSymbolName, tint: attributes.routineTint, size: 20)
    }

    static func compactTrailing(_ state: RestActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startDate...state.endDate, countsDown: true)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(WidgetPalette.ink)
    }

    static func minimal(_ state: RestActivityAttributes.ContentState) -> some View {
        RestRing(state: state)
    }
}
