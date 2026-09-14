import AppIntents
import SwiftUI

/// "+30S" / "SKIP" / "SET DONE" — the three interactive buttons on the Lock Screen banner and the
/// Dynamic Island expanded presentation, both driven by the same `LiveActivityIntent`s.
struct RestButtonRow: View {
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: AddRestTimeIntent()) { Text("+30S") }
                .tint(palette.inkMuted)
            Button(intent: SkipRestIntent()) { Text("SKIP") }
                .tint(palette.inkMuted)
            Button(intent: MarkSetDoneIntent()) { Text("SET DONE") }
                .tint(palette.green)
                .foregroundStyle(palette.inkOnAccent)
        }
        .buttonStyle(.borderedProminent)
        .font(.caption.weight(.bold))
    }
}
