import SwiftUI
import WidgetKit

/// Lock Screen banner for the rest timer. See mockup 03b
/// (scratchpad/mock/03_01.png, left column): micro label + routine name, ring + countdown,
/// "Next: …", then the three action buttons.
struct RestLockScreenView: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 14) {
                RestRing(state: state).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timerInterval: state.startDate...state.endDate, countsDown: true)
                        .font(WidgetFont.condensed(size: 34))
                        .foregroundStyle(WidgetPalette.ink)
                    Text("Next: \(state.nextSetLabel)")
                        .font(.footnote)
                        .foregroundStyle(WidgetPalette.inkMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            RestButtonRow()
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                RoutineWidgetGlyph(
                    symbolName: attributes.routineSymbolName, tint: attributes.routineTint, size: 16
                )
                Text("DAGYM · REST")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(WidgetPalette.inkMuted)
            }
            Spacer()
            Text(attributes.workoutTitle.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(WidgetPalette.inkMuted)
        }
    }
}
