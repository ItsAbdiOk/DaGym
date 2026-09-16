import SwiftUI

/// The undo pill's quieter sibling: one line ("Copied") at the bottom that goes away on its
/// own. For confirmations with nothing to undo — a clipboard write, a share that finished.
private struct NoticeToastModifier: ViewModifier {
    @Binding var message: String?
    var seconds: Double

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(2)
                    .padding(.horizontal, DGSpace.s5)
                    .frame(minHeight: 44)
                    .dgGlass(.thick, in: Capsule())
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.bottom, DGSpace.s4)
                    .dgTransition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(seconds))
                        guard !Task.isCancelled, self.message == message else { return }
                        self.message = nil
                    }
            }
        }
        .dgAnimation(DGMotion.standard, value: message)
    }
}

extension View {
    /// Shows `message` as a pill at the bottom of this view until `seconds` pass. Set the
    /// binding after each confirmation; a newer message replaces the pill and restarts the clock.
    func dgNoticeToast(_ message: Binding<String?>, seconds: Double = 2) -> some View {
        modifier(NoticeToastModifier(message: message, seconds: seconds))
    }
}

#Preview {
    @Previewable @State var message: String? = "Copied"
    Color.clear
        .background(DGColor.bgBase)
        .dgNoticeToast($message)
}
