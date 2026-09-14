import SwiftUI

/// The mic entry point: press-and-hold to talk, release to log. VoiceOver can't reliably hold a
/// touch down (that gesture is reserved for its own "activate and hold" behaviour and is easy to
/// trigger by accident), so it gets a second way in — a single-tap toggle via
/// `.accessibilityAction` — documented in the hint below.
struct HoldToTalkButton: View {
    var isListening: Bool
    var onPressDown: () -> Void
    var onRelease: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        Circle()
            .fill(isListening ? DGColor.coral : DGColor.surface2)
            .overlay {
                Circle().strokeBorder(isListening ? Color.clear : DGColor.hairline, lineWidth: 1)
            }
            .overlay {
                Image(systemName: isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isListening ? DGColor.inkOnCoral : DGColor.ink1)
            }
            .frame(width: 52, height: 52)
            .scaleEffect(isPressed ? 1.08 : 1)
            .shadow(color: isListening ? DGColor.coral.opacity(0.4) : .clear, radius: 12, y: 4)
            .animation(DGMotion.tap, value: isListening)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed, !voiceOverEnabled else { return }
                        isPressed = true
                        Haptics.press()
                        onPressDown()
                    }
                    .onEnded { _ in
                        guard !voiceOverEnabled else { return }
                        isPressed = false
                        onRelease()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voice log a set")
            .accessibilityHint(
                voiceOverEnabled
                    ? "Double tap to start listening, then double tap again to log what you said."
                    : "Press and hold, say a set, then release to log it."
            )
            .accessibilityAddTraits(isListening ? [.startsMediaSession] : [])
            .accessibilityAction {
                guard voiceOverEnabled else { return }
                if isListening { onRelease() } else { onPressDown() }
            }
    }
}

#Preview {
    HoldToTalkButton(isListening: false, onPressDown: {}, onRelease: {})
        .padding()
        .background(DGColor.bgBase)
}
