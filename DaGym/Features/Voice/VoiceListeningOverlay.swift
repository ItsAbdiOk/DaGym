import SwiftUI

/// Glass pill shown while the mic is held: a pulsing dot plus the live partial transcript, so the
/// user can see what's being heard before they release. Placeholder styling — see
/// `VoiceReviewCard`'s header comment; this shares the same "re-skin later" status.
struct VoiceListeningOverlay: View {
    var partialTranscript: String

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Circle()
                .fill(DGColor.coral)
                .frame(width: 8, height: 8)
                // Reduce Motion keeps the opacity pulse (a fade, not a move) and drops the scale.
                .scaleEffect(pulse && !reduceMotion ? 1.6 : 1)
                .opacity(pulse ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
                .accessibilityHidden(true)
            Text(partialTranscript.isEmpty ? "Listening…" : partialTranscript)
                .font(DGFont.body)
                .foregroundStyle(partialTranscript.isEmpty ? DGColor.ink3 : DGColor.ink1)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .accessibilityLabel(
                    partialTranscript.isEmpty ? "Listening" : "Heard so far: \(partialTranscript)"
                )
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgGlass(.thick, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
    }
}

#Preview {
    VoiceListeningOverlay(partialTranscript: "two twenty five for eight")
        .padding()
        .background(DGColor.bgBase)
}
