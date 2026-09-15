import SwiftUI

/// "Talk to your coach" at the top of the Coach tab. With a key and consent it opens
/// `CoachChatView` full screen; without, it says what's missing and opens Settings instead, so
/// the tab never advertises a coach that can't answer. Violet, not coral: this is the one
/// feature on the tab that sends data off the phone, and the app's AI accent says so.
struct CoachChatEntryCard: View {
    @Environment(Preferences.self) private var preferences
    @State private var showingChat = false
    @State private var showingSettings = false
    /// Re-read on every appearance and foreground so a key saved in Settings flips the card.
    @State private var hasKey = CoachChatSettings.hasAPIKey

    private var isReady: Bool { hasKey && preferences.coachChatConsentGiven }

    var body: some View {
        Button {
            if isReady { showingChat = true } else { showingSettings = true }
        } label: {
            HStack(alignment: .top, spacing: DGSpace.s3) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DGColor.aiVioletText)
                    .frame(width: 40, height: 40)
                    .background(
                        DGColor.surface3, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text("Talk to your coach")
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    Text(caption)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DGSpace.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
                    .padding(.top, DGSpace.s1)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dgCard(padding: DGSpace.s4)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Talk to your coach. \(caption)")
        .accessibilityIdentifier(A11yID.coachChatEntry)
        .fullScreenCover(isPresented: $showingChat) { CoachChatView() }
        .sheet(
            isPresented: $showingSettings, onDismiss: { hasKey = CoachChatSettings.hasAPIKey },
            content: { SettingsView() }
        )
        .onAppear { hasKey = CoachChatSettings.hasAPIKey }
    }

    private var caption: String {
        if !hasKey {
            "Ask anything about your training and get routines built for you. Add your OpenRouter "
                + "key in Settings to start."
        } else if !preferences.coachChatConsentGiven {
            "Agree to what's sent in Settings to start chatting."
        } else {
            "Ask about your progress, volume or plan. It reads your log and proposes changes you can "
                + "apply with one tap."
        }
    }
}

#Preview {
    CoachChatEntryCard()
        .padding()
        .environment(Preferences())
        .background(AmbientWash())
}
