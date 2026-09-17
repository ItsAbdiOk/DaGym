import SwiftUI

/// The prototype's speech bubble: 20 pt corners with one 6 pt corner at the bottom on the
/// speaker's side, so a run of bubbles reads as a conversation rather than a stack of cards.
struct CoachBubbleShape: InsettableShape {
    enum Tail { case leading, trailing, none }

    var tail: Tail
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let small: CGFloat = 6
        let large: CGFloat = 20
        return UnevenRoundedRectangle(
            topLeadingRadius: large, bottomLeadingRadius: tail == .leading ? small : large,
            bottomTrailingRadius: tail == .trailing ? small : large, topTrailingRadius: large,
            style: .continuous
        )
        .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> CoachBubbleShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// The coach's bubble material: the card recipe at bubble size (white at 75 % over the wash
/// with a bright half-point edge), so the transcript is the same material as the rest of the
/// app and never a second, flatter white.
struct CoachBubbleMaterial: ViewModifier {
    var tail: CoachBubbleShape.Tail
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = CoachBubbleShape(tail: tail)
        content
            .background {
                shape.fill(.white.opacity(scheme == .dark ? 0.08 : 0.75))
                    .background(.ultraThinMaterial, in: shape)
            }
            .overlay { shape.strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.9), lineWidth: 0.5) }
    }
}

extension View {
    func coachBubble(tail: CoachBubbleShape.Tail = .leading) -> some View {
        modifier(CoachBubbleMaterial(tail: tail))
    }
}

/// What the coach is doing, as one bubble: each tool the turn has called so far on its own
/// line ("Reading your schedule", "Searching exercises ×2"), and "Thinking…" under them while
/// the reply has not started. Shimmers while the turn runs; a finished turn's trail stays as a
/// plain record of what was read, which is the citation the coach owes for its numbers.
struct CoachToolTrailBubble: View {
    var lines: [CoachChatTranscript.ToolLine]
    var isThinking: Bool
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(lines, id: \.self) { line in
                    HStack(spacing: DGSpace.s1) {
                        if line.failed {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(line.text)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(line.failed ? DGColor.warning : DGColor.ink3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line.failed ? "\(line.text), failed" : line.text)
                    .accessibilityIdentifier(A11yID.coachChatToolChip)
                }
                if isThinking {
                    Text("Thinking…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DGColor.ink3)
                        .accessibilityLabel("Coach is thinking")
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .coachBubble(tail: .none)
            .opacity(isThinking && shimmer ? 0.72 : 1)
            .animation(
                isThinking ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true) : .default,
                value: shimmer
            )
            // Reduce Motion: no pulse — the "thinking" bubble simply shows at full opacity.
            .onAppear { shimmer = isThinking && !reduceMotion }
            .onChange(of: isThinking) { _, thinking in shimmer = thinking && !reduceMotion }
            Spacer(minLength: DGSpace.s10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isThinking ? "Coach is working" : "What the coach read")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DGSpace.s3) {
        CoachToolTrailBubble(
            lines: [
                .init(label: "Reading your schedule", count: 1, failed: false),
                .init(label: "Searching exercises · chest", count: 2, failed: false)
            ],
            isThinking: true
        )
        CoachToolTrailBubble(
            lines: [.init(label: "Reading exercise history", count: 1, failed: true)], isThinking: false
        )
    }
    .padding()
    .background(AmbientWash())
}
