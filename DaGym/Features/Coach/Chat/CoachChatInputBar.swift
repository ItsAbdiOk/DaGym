import SwiftUI

/// The chat's bottom bar: a growing text field and one round button that sends, or stops the
/// stream while a reply is in flight. Same glyphs and violet as `CoachAskSection` so the two
/// coach inputs feel like one control.
struct CoachChatInputBar: View {
    @Binding var text: String
    var isStreaming: Bool
    var isEnabled: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DGSpace.s2) {
            TextField("Ask your coach", text: $text, axis: .vertical)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1...5)
                .padding(.horizontal, DGSpace.s4)
                .padding(.vertical, DGSpace.s3)
                .frame(minHeight: DGTap.min)
                .dgCard(radius: DGRadius.xl, padding: 0)
                .focused($isFocused)
                .disabled(!isEnabled)
                .accessibilityIdentifier(A11yID.coachChatInput)
            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DGColor.ink1)
                        .frame(width: DGTap.min, height: DGTap.min)
                        .background(DGColor.surface3, in: Circle())
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel("Stop")
                .accessibilityIdentifier(A11yID.coachChatStop)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: DGTap.min, height: DGTap.min)
                        .background(canSend ? DGColor.aiViolet : DGColor.surface3, in: Circle())
                }
                .buttonStyle(.dgControl)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier(A11yID.coachChatSend)
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.vertical, DGSpace.s2)
    }
}

#Preview {
    VStack {
        Spacer()
        CoachChatInputBar(
            text: .constant("When will I bench 100 kg?"), isStreaming: false, isEnabled: true,
            onSend: {}, onStop: {}
        )
        CoachChatInputBar(text: .constant(""), isStreaming: true, isEnabled: true, onSend: {}, onStop: {})
    }
    .background(AmbientWash())
}
