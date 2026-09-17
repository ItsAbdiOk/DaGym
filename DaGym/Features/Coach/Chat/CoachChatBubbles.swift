import GymCore
import SwiftUI

/// One transcript entry as the chat screen draws it: a right-aligned coral bubble for the
/// lifter, a left-aligned card for the coach (paragraphs and bullets, a "stopped" marker when
/// the reply was cut short), a compact activity chip while a tool runs, or the reviewer's
/// verdict line. Draft cards are `CoachDraftCard`, drawn by the screen because they need the
/// draft and its state; `review` is the matching entry of the engine's `reviews`, when known.
struct CoachChatMessageRow: View {
    var message: CoachChatMessage
    var review: CoachChatReview?
    /// False for the turn still in flight, so a reply never folds while it is being read.
    var canFold = false
    @Binding var isExpanded: Bool
    var onCopy: () -> Void = {}
    /// Where the words can be kept besides the clipboard; asked only when the menu opens, since
    /// the screen scans the library to answer.
    var saveTargets: () -> [CoachChatSaveTarget] = { [] }
    var onSave: (CoachChatSaveTarget) -> Void = { _ in }

    var body: some View {
        switch message.role {
        case .user: CoachUserBubble(text: message.text)
        case .assistant:
            if message.isNote == true {
                CoachNoteRow(text: message.text)
            } else {
                CoachAssistantBubble(
                    text: message.text, isStopped: message.isStopped, canFold: canFold,
                    isExpanded: $isExpanded, onCopy: onCopy, saveTargets: saveTargets, onSave: onSave
                )
            }
        case .tool: CoachToolChip(label: message.text, failed: message.isToolError)
        case .draft: EmptyView()
        case .review:
            CoachReviewRow(
                text: message.text, review: review, canFold: canFold, isExpanded: $isExpanded, onCopy: onCopy,
                saveTargets: saveTargets, onSave: onSave
            )
        }
    }
}

/// The long-press menu every coach bubble and card shares: Copy, then one "Save as note for
/// <Exercise>" per exercise the text names, then "Remember this". Each item says where the
/// text ends up for VoiceOver.
struct CoachChatSaveMenu: View {
    var targets: [CoachChatSaveTarget]
    var onCopy: () -> Void
    var onSave: (CoachChatSaveTarget) -> Void

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc", action: onCopy)
        ForEach(targets) { target in
            Button(target.menuLabel, systemImage: target.symbol) { onSave(target) }
                .accessibilityLabel(target.accessibilityLabel)
        }
    }
}

/// The second opinion's verdict as one compact transcript line: a green tick when the
/// reviewer agreed, a violet arrow when it proposed its own version (the card follows), a
/// muted mark when the review failed. The text is the engine's line; the review only picks
/// the tone and the accessibility label.
struct CoachReviewRow: View {
    var text: String
    var review: CoachChatReview?
    var canFold = false
    @Binding var isExpanded: Bool
    var onCopy: () -> Void = {}
    var saveTargets: () -> [CoachChatSaveTarget] = { [] }
    var onSave: (CoachChatSaveTarget) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s2) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let review {
                    Text(CoachReviewCopy.transcriptLine(for: review))
                        .font(DGFont.condensedLabel(12))
                        .tracking(0.8)
                        .textCase(.uppercase)
                }
                if !text.isEmpty {
                    CoachFoldedText(
                        text: text, canFold: canFold, isExpanded: $isExpanded,
                        font: DGFont.footnote, color: tint
                    )
                }
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: 28)
        .contextMenu {
            if !text.isEmpty {
                CoachChatSaveMenu(targets: saveTargets(), onCopy: onCopy, onSave: onSave)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(review.map { CoachReviewCopy.transcriptLine(for: $0) } ?? "Review")
        .accessibilityIdentifier(A11yID.coachChatReviewRow)
    }

    private var symbol: String {
        switch review?.verdict {
        case .agreed: "checkmark.circle"
        case .alternative: "arrow.turn.down.right"
        case .failed: "exclamationmark.circle"
        case nil: "text.bubble"
        }
    }

    private var tint: Color {
        switch review?.verdict {
        case .agreed: DGColor.success
        case .alternative: DGColor.aiVioletText
        case .failed, nil: DGColor.ink4
        }
    }
}

struct CoachUserBubble: View {
    var text: String

    var body: some View {
        HStack {
            Spacer(minLength: DGSpace.s10)
            Text(text)
                .font(DGFont.body)
                .foregroundStyle(DGColor.inkOnCoral)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DGSpace.s4)
                .padding(.vertical, DGSpace.s3)
                .background(
                    DGColor.coral, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You: \(text)")
        .accessibilityIdentifier(A11yID.coachChatUserBubble)
    }
}

/// The coach's words. Markdown-lite rendered by `CoachFoldedText`, which also folds a long
/// reply; long-press offers Copy (plain text, markers stripped), a note on each exercise the
/// reply names, and "Remember this" (`CoachChatSaveMenu`). The bubble is one VoiceOver
/// container: the text's own elements (a paragraph, each list item) read in order, then the
/// "stopped" marker and the Show more button.
struct CoachAssistantBubble: View {
    var text: String
    var isStopped: Bool
    var canFold = false
    @Binding var isExpanded: Bool
    var onCopy: () -> Void = {}
    var saveTargets: () -> [CoachChatSaveTarget] = { [] }
    var onSave: (CoachChatSaveTarget) -> Void = { _ in }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                CoachFoldedText(text: text, canFold: canFold, isExpanded: $isExpanded)
                if text.isEmpty, !isStopped {
                    // The reply hasn't started arriving yet; three dots rather than an empty card.
                    Text("…")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink4)
                        .accessibilityLabel("Coach is thinking")
                }
                if isStopped {
                    Text("Stopped")
                        .font(DGFont.condensedLabel(11))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .padding(DGSpace.s4)
            .dgCard(padding: 0)
            .contextMenu {
                if !text.isEmpty {
                    CoachChatSaveMenu(targets: saveTargets(), onCopy: onCopy, onSave: onSave)
                }
            }
            Spacer(minLength: DGSpace.s8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Coach")
        .accessibilityIdentifier(A11yID.coachChatAssistantBubble)
    }
}

/// "Reading exercise history" while the store answers a tool call; a failed call is marked but
/// not alarming — the model gets the error and explains or retries in its own words.
struct CoachToolChip: View {
    var label: String
    var failed: Bool
    /// How many consecutive identical tool calls this chip stands for; shown as "×N" past one.
    var count: Int = 1

    var body: some View {
        HStack(spacing: DGSpace.s1) {
            Image(systemName: failed ? "exclamationmark.circle" : "sparkle.magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(count > 1 ? "\(label) ×\(count)" : label)
                .font(DGFont.condensedLabel(12))
                .tracking(0.8)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .foregroundStyle(failed ? DGColor.warning : DGColor.aiVioletText)
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: 28)
        .background(Capsule().fill(DGColor.surface2).overlay(Capsule().strokeBorder(DGColor.hairline)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(failed ? "\(label), failed" : label)
        .accessibilityIdentifier(A11yID.coachChatToolChip)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DGSpace.s3) {
        CoachUserBubble(text: "When will I bench 100 kg?")
        CoachToolChip(label: "Reading exercise history", failed: false)
        CoachAssistantBubble(
            text: "At your current pace, around **late November**.\n\n- 12 sessions read\n- +1.2 kg a week",
            isStopped: false, isExpanded: .constant(false)
        )
    }
    .padding()
    .background(AmbientWash())
}

/// The pause before the first words: the model is reading tools or composing, and an empty
/// transcript for ten seconds reads as "nothing is happening".
struct CoachThinkingRow: View {

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            ProgressView()
                .controlSize(.small)
                .tint(DGColor.aiVioletText)
            Text("Thinking…")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach is thinking")
    }
}

/// An app-written line in the transcript — why a turn ended without a reply.
struct CoachNoteRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s2) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(DGFont.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DGColor.warning)
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}
