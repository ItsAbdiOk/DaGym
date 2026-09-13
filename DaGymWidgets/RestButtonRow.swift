import AppIntents
import SwiftUI

/// "+30S" / "SKIP" / "SET DONE" — the three interactive buttons on the Lock Screen banner and the
/// Dynamic Island expanded presentation, both driven by the same `LiveActivityIntent`s.
struct RestButtonRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: AddRestTimeIntent()) { Text("+30S") }
                .tint(WidgetPalette.inkMuted)
            Button(intent: SkipRestIntent()) { Text("SKIP") }
                .tint(WidgetPalette.inkMuted)
            Button(intent: MarkSetDoneIntent()) { Text("SET DONE") }
                .tint(WidgetPalette.green)
                .foregroundStyle(WidgetPalette.inkOnCoral)
        }
        .buttonStyle(.borderedProminent)
        .font(.caption.weight(.bold))
    }
}
