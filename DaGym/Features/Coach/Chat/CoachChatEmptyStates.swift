import SwiftUI

/// The chat screen before it can send: no key, or a key without consent. Drawn in the
/// transcript's own voice — one coach bubble saying what's missing and a pill that opens
/// Settings, where the key sheet and the consent screen live — so the screen never advertises
/// a coach that can't answer, and never looks like a different app than the chat it becomes.
struct CoachChatSetupState: View {
    var hasKey: Bool
    var onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                CoachChatOpeningBubble(text: message)
                Button(action: onOpenSettings) {
                    Text("Open Settings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                        .padding(.horizontal, DGSpace.s5)
                        .frame(minHeight: 40)
                        .background(DGColor.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.dgControl)
                Text("Your key stays in the Keychain and nothing is sent until you ask a question.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s4)
        }
    }

    private var message: String {
        hasKey
            ? "Agree to what's sent in Settings before I can read your training."
            : "Ask anything about your training and get routines built for you. Add your OpenRouter "
                + "key in Settings to start."
    }
}

/// The coach's first bubble on an empty thread — the week so far from the real recap, or the
/// setup line above. Tapping it puts the cursor in the input: it is the one control the
/// screen's UI test reaches for first (`coach.chat.entry`), and a bubble that asks a question
/// should be where the answer starts.
struct CoachChatOpeningBubble: View {
    var text: String
    var onTap: () -> Void = {}

    var body: some View {
        HStack {
            Button(action: onTap) {
                Text(text)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .coachBubble()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Coach: \(text)")
            .accessibilityIdentifier(A11yID.coachChatEntry)
            Spacer(minLength: DGSpace.s10)
        }
    }
}

#Preview {
    VStack {
        CoachChatSetupState(hasKey: false, onOpenSettings: {})
        CoachChatOpeningBubble(
            text: "Your week is done: 3 of 4 sessions, 47,200 kg of volume, one PR. Want the review?"
        )
        .padding(.horizontal, DGSpace.s4)
    }
    .background(AmbientWash())
}
