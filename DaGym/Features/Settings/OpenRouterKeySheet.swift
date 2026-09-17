import SwiftUI

/// The OpenRouter key sheet, shaped like `HevyAPIKeySheet`: a `SecureField` (the key is never
/// echoed, and never pre-filled — the Keychain value is not read back into the UI), Save, and
/// Remove when one is stored. The caller writes the Keychain; this view only hands over text.
struct OpenRouterKeySheet: View {
    var hasKey: Bool
    var onSave: (String) -> Void
    var onRemove: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("OpenRouter API Key")
                    .font(DGFont.title2)
                    .foregroundStyle(DGColor.ink1)
                Text(
                    "From openrouter.ai → Keys. Stored in the Keychain and sent only to OpenRouter, "
                        + "with each question you ask the coach."
                )
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SecureField(hasKey ? "Paste a new key to replace the saved one" : "Paste your key", text: $draft)
                .textFieldStyle(.plain)
                .font(DGFont.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textContentType(.password)
                .padding(DGSpace.s4)
                .dgCard(padding: 0)
                .accessibilityLabel("OpenRouter API key")
                .accessibilityIdentifier(A11yID.coachKeyField)
            DGPrimaryButton(title: "Save", action: save)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier(A11yID.coachKeySave)
            if hasKey {
                Button("Remove Key", role: .destructive, action: onRemove)
                    .buttonStyle(.dgControl)
                    .dgLabel(DGColor.danger)
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
    }

    private func save() {
        onSave(draft.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

#Preview {
    OpenRouterKeySheet(hasKey: true, onSave: { _ in }, onRemove: {})
}
