import SwiftUI

/// The chat's bottom bar from the prototype: a row of prompt chips that scrolls sideways, then
/// one white pill holding the growing text field and a round accent button that sends — or
/// stops the stream while a reply is in flight. The screen owns the chips (one leads with
/// "Review my week" when a review is waiting) and the focus, so the opening bubble can put
/// the cursor here.
struct CoachChatInputBar: View {
    @Binding var text: String
    var isStreaming: Bool
    var isEnabled: Bool
    var chips: [String] = []
    var focus: FocusState<Bool>.Binding
    var onChip: (String) -> Void = { _ in }
    var onSend: () -> Void
    var onStop: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 9) {
            if !chips.isEmpty, isEnabled {
                chipRow
            }
            pill
                .padding(.horizontal, DGSpace.s4)
        }
        .padding(.top, 10)
        .padding(.bottom, DGSpace.s2)
        .background(alignment: .top) {
            Rectangle().fill(DGColor.hairline).frame(height: 0.5)
        }
        .background(DGColor.bgBase.opacity(scheme == .dark ? 0.7 : 0.86))
        .background(.ultraThinMaterial)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(chips, id: \.self) { chip in
                    Button { onChip(chip) } label: {
                        Text(chip)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(DGColor.ink1)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(.white.opacity(scheme == .dark ? 0.1 : 0.8), in: Capsule())
                            .overlay(Capsule().strokeBorder(DGColor.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.dgControl)
                    .disabled(isStreaming)
                    .accessibilityIdentifier(A11yID.coachChatSuggestedPrompt)
                }
            }
            .padding(.horizontal, DGSpace.s4)
        }
        .scrollClipDisabled()
    }

    private var pill: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("Ask your coach", text: $text, axis: .vertical)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1...5)
                .padding(.vertical, 7)
                .focused(focus)
                .disabled(!isEnabled)
                .accessibilityIdentifier(A11yID.coachChatInput)
            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DGColor.ink1)
                        .frame(width: 30, height: 30)
                        .background(DGColor.surface3, in: Circle())
                        .frame(width: DGTap.min, height: DGTap.min)
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel("Stop")
                .accessibilityIdentifier(A11yID.coachChatStop)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DGColor.inkOnCoral)
                        .frame(width: 30, height: 30)
                        .background(DGColor.coral.opacity(canSend ? 1 : 0.45), in: Circle())
                        .frame(width: DGTap.min, height: DGTap.min)
                }
                .buttonStyle(.dgControl)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier(A11yID.coachChatSend)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            .white.opacity(scheme == .dark ? 0.1 : 0.85),
            in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 0.5)
        }
    }
}

#Preview {
    @Previewable @FocusState var focus: Bool
    return VStack {
        Spacer()
        CoachChatInputBar(
            text: .constant("When will I bench 100 kg?"), isStreaming: false, isEnabled: true,
            chips: CoachChatOpening.chips(reviewDue: true), focus: $focus, onSend: {}, onStop: {}
        )
        CoachChatInputBar(
            text: .constant(""), isStreaming: true, isEnabled: true, focus: $focus, onSend: {}, onStop: {}
        )
    }
    .background(AmbientWash())
}
