import SwiftUI

/// The mic entry point: press-and-hold to talk, release to log. VoiceOver can't reliably hold a
/// touch down (that gesture is reserved for its own "activate and hold" behaviour and is easy to
/// trigger by accident), so it gets a second way in — a single-tap toggle via
/// `.accessibilityAction` — documented in the hint below.
///
/// The held state is a `@GestureState`, not plain `@State`, because teardown must not depend on
/// `onEnded` firing. Anything that cancels the drag — the two system permission alerts, an error
/// alert appearing under the finger, a scroll stealing the gesture — skips `onEnded` entirely,
/// which used to leave the pressed flag stuck `true`: the next press was dead and the mic and
/// engine stayed hot. SwiftUI resets a `@GestureState` on cancellation as well as on a clean end,
/// so `onChange` below is the single place release is handled, whichever way the gesture died.
struct HoldToTalkButton: View {
    var isListening: Bool
    var onPressDown: () -> Void
    var onRelease: () -> Void

    @GestureState private var isHeld = false
    /// Guards against a stray release: only a press this view actually started may end.
    @State private var didPressDown = false
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
            .scaleEffect(isHeld ? 1.08 : 1)
            .shadow(color: isListening ? DGColor.coral.opacity(0.4) : .clear, radius: 12, y: 4)
            .animation(DGMotion.tap, value: isListening)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isHeld) { _, held, _ in held = true }
            )
            .onChange(of: isHeld) { _, held in
                guard !voiceOverEnabled else { return }
                if held {
                    didPressDown = true
                    Haptics.press()
                    onPressDown()
                } else if didPressDown {
                    didPressDown = false
                    onRelease()
                }
            }
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
