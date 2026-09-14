import SwiftUI
import WidgetKit

/// The coral countdown ring shared by the Lock Screen banner, Dynamic Island minimal presentation
/// and the expanded leading region.
struct RestRing: View {
    let state: RestActivityAttributes.ContentState

    @Environment(\.widgetPalette) private var palette

    var body: some View {
        ProgressView(
            timerInterval: state.startDate...state.endDate, countsDown: true,
            label: { EmptyView() }, currentValueLabel: { EmptyView() }
        )
        .progressViewStyle(.circular)
        .tint(palette.accent)
    }
}
