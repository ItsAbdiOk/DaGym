import SwiftUI

/// One reversible action shown in a `dgUndoToast`: the message and the closure that undoes it.
struct UndoAction: Identifiable {
    let id = UUID()
    var message: String
    var undo: () -> Void
}

/// Bottom-anchored glass pill — "Deleted set · UNDO" — that auto-dismisses after `seconds`.
/// Tapping UNDO runs the action and dismisses at once; a newer action replaces the pill and
/// restarts the clock.
private struct UndoToastModifier: ViewModifier {
    @Binding var action: UndoAction?
    var seconds: Double

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let action {
                UndoToast(message: action.message) {
                    action.undo()
                    self.action = nil
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.bottom, DGSpace.s4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: action.id) {
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled, self.action?.id == action.id else { return }
                    self.action = nil
                }
            }
        }
        .animation(DGMotion.standard, value: action?.id)
    }
}

private struct UndoToast: View {
    var message: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Text(message)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
            Text("·")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink4)
            Button(action: onUndo) {
                Text("Undo")
                    .font(DGFont.condensedLabel(13))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.coralText)
                    .frame(minHeight: DGTap.min)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo, \(message)")
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(height: 48)
        .dgGlass(.thick, in: Capsule())
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Shows `action` as an undo pill at the bottom of this view until `seconds` pass or UNDO
    /// is tapped. Set the binding to a new `UndoAction` after each reversible edit.
    func dgUndoToast(_ action: Binding<UndoAction?>, seconds: Double = 5) -> some View {
        modifier(UndoToastModifier(action: action, seconds: seconds))
    }
}

#Preview {
    @Previewable @State var action: UndoAction? = UndoAction(message: "Deleted set", undo: {})
    Color.clear
        .background(DGColor.bgBase)
        .dgUndoToast($action)
}
