import SwiftUI

/// The chat screen before it can send: no key, or a key without consent. Both point at
/// Settings, where the key sheet and the consent screen live.
struct CoachChatSetupState: View {
    var hasKey: Bool
    var onOpenSettings: () -> Void

    var body: some View {
        VStack {
            Spacer()
            EmptyState(
                symbol: "key",
                title: "Set Up Your Coach",
                message: hasKey
                    ? "Agree to what's sent in Settings before the coach can read your training."
                    : "Add your OpenRouter API key in Settings. Your key stays in the Keychain and "
                        + "nothing is sent until you ask a question.",
                action: "Open Settings", onAction: onOpenSettings
            )
            .padding(.horizontal, DGSpace.s6)
            Spacer()
        }
    }
}

/// An empty thread's opening: three prompts to tap, and a line on how proposals arrive.
struct CoachChatSuggestedPromptsView: View {
    var onPick: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                Text("Try asking").dgLabel()
                ForEach(CoachChatSuggestedPrompts.all, id: \.self) { prompt in
                    Button {
                        onPick(prompt)
                    } label: {
                        HStack {
                            Text(prompt)
                                .font(DGFont.body)
                                .foregroundStyle(DGColor.ink1)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DGSpace.s2)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DGColor.aiVioletText)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dgCard(padding: DGSpace.s4)
                    }
                    .buttonStyle(.dgControl)
                    .accessibilityIdentifier(A11yID.coachChatSuggestedPrompt)
                }
                Text("The coach reads your log through tools and cites what it used. Proposals arrive as "
                    + "cards you apply or discard — nothing changes until you tap Apply.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DGSpace.s2)
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s5)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview {
    VStack {
        CoachChatSetupState(hasKey: false, onOpenSettings: {})
        CoachChatSuggestedPromptsView(onPick: { _ in })
    }
    .background(AmbientWash())
}
