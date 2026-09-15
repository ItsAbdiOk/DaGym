import SwiftUI

/// Typed-confirm gate in front of `WorkoutStore.wipeAllData(preferences:)` — the delete button
/// stays disabled until the user types "DELETE" exactly, so a destructive row can't fire from a
/// stray tap or a misread confirmation alert.
struct ResetAllDataSheet: View {
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    /// Not private: `SettingsSectionsTests` pins the word the sheet demands.
    static let confirmationWord = "DELETE"

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            HStack {
                Text("Reset Everything").font(DGFont.title2).foregroundStyle(DGColor.ink1)
                Spacer()
                DGIconButton(symbol: "xmark", accessibilityLabel: "Close") { dismiss() }
            }
            Text(
                "This permanently deletes every routine, workout, exercise, progress photo and "
                    + "setting on this device. It can't be undone."
            )
            .font(DGFont.body)
            .foregroundStyle(DGColor.ink3)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Type DELETE to confirm").font(DGFont.footnote).foregroundStyle(DGColor.ink4)
                TextField(Self.confirmationWord, text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(DGFont.body)
                    .padding(DGSpace.s3)
                    .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            DGPrimaryButton(title: "Delete Everything", symbol: "trash", fill: DGColor.danger, height: 52) {
                onConfirm()
                dismiss()
            }
            .disabled(typed != Self.confirmationWord)
            .opacity(typed == Self.confirmationWord ? 1 : 0.4)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s6)
        .padding(.bottom, DGSpace.s8)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
    }
}

#Preview {
    ResetAllDataSheet(onConfirm: {})
}
