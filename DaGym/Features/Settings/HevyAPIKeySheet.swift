import SwiftUI

/// A single API-key text field, presented the first time "Import from Hevy" is tapped and
/// reachable again from the same row afterward to remove the key.
struct HevyAPIKeySheet: View {
    var apiKey: String
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
                Text("Hevy API Key")
                    .font(DGFont.title2)
                    .foregroundStyle(DGColor.ink1)
                Text(
                    "From hevy.app → Settings → API (Hevy Pro). Stored in the Keychain — it's only "
                        + "ever sent to Hevy's own API."
                )
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("API key", text: $draft)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(DGSpace.s4)
                .dgCard(padding: 0)
            DGPrimaryButton(title: "Connect", action: save)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !apiKey.isEmpty {
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
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .task { draft = apiKey }
    }

    private func save() {
        onSave(draft.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

#Preview {
    HevyAPIKeySheet(apiKey: "", onSave: { _ in }, onRemove: {})
}
