import SwiftUI

/// `CoachChatScreen` in its own stack, for the full-screen covers that still open the coach
/// from elsewhere (Home's week-review card, "Ask the coach" from empty states). The You hub
/// pushes the screen directly; only a cover needs the stack and its Close button.
struct CoachChatView: View {
    /// nil opens the newest thread; a week review opens (or starts) that week's review thread.
    var launch: CoachChatLaunch?

    var body: some View {
        NavigationStack {
            CoachChatScreen(launch: launch, isPresentedModally: true)
                .screenDestinations()
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        CoachChatView()
            .environment(store)
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
