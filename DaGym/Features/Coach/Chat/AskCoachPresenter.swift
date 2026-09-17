import SwiftUI

/// Whether the cloud coach can answer right now — a key in the Keychain and consent given.
/// The empty states that offer "Ask the coach" route through Settings when it can't, exactly
/// as the chat screen's own setup state does.
@MainActor
enum CoachChatReadiness {
    static func isReady(_ preferences: Preferences) -> Bool {
        CoachChatSettings.hasAPIKey && preferences.coachChatConsentGiven
    }
}

/// "Ask the coach" from an empty state: opens the chat full screen when it's ready, Settings
/// (where the key and consent live) when it isn't. `trigger` is the caller's tap flag.
struct AskCoachPresenter: ViewModifier {
    @Binding var trigger: Bool
    @Environment(Preferences.self) private var preferences
    @State private var showingChat = false
    @State private var showingSettings = false

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, tapped in
                guard tapped else { return }
                trigger = false
                if CoachChatReadiness.isReady(preferences) {
                    showingChat = true
                } else {
                    showingSettings = true
                }
            }
            .fullScreenCover(isPresented: $showingChat) { CoachChatView() }
            .sheet(isPresented: $showingSettings) { SettingsView(standalone: true) }
    }
}

extension View {
    /// Presents the coach chat (or Settings) whenever `trigger` flips to true, then resets it.
    func askCoach(on trigger: Binding<Bool>) -> some View {
        modifier(AskCoachPresenter(trigger: trigger))
    }
}
