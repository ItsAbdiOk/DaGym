import GymCore
import SwiftUI

/// One `CoachCard` as the Insights screen draws it: a kicker with the severity dot
/// ("WARNING · DELOAD OVERDUE"), the title, the one-sentence claim, a "Why?" box with the
/// evidence, a line on what the action really does, then the action next to "Not now".
/// See `InsightsScreen` for the screen this tiles into.
struct CoachCardView: View {
    var card: CoachCard
    var formatWeight: (Double) -> String
    var onApprove: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker
            Text(card.title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            Text(card.body)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            if !card.evidence.isEmpty {
                whyBox.padding(.top, DGSpace.s3)
            }
            if let note = CoachCardCopy.actionNote(for: card.suggestedAction, formatWeight: formatWeight) {
                Text(note)
                    .font(DGFont.caption)
                    .fontWeight(.regular)
                    .foregroundStyle(DGColor.ink4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DGSpace.s2)
            }
            actions.padding(.top, DGSpace.s3)
        }
        .dgCard(radius: 20, padding: DGSpace.s4)
    }

    private var kicker: some View {
        HStack(spacing: DGSpace.s2) {
            // Severity is the dot's colour *and* its shape: a triangle for a warning, a filled
            // circle for a notice, a ring for information — so it survives colour-blindness.
            severityGlyph
            Text("\(Self.severityWord(card.severity)) · \(CoachCardCopy.kicker(for: card.rule))")
                .dgLabel()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.severityWord(card.severity)): \(card.title)")
    }

    @ViewBuilder
    private var severityGlyph: some View {
        switch card.severity {
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(severityColor)
        case .notice:
            Circle().fill(severityColor).frame(width: 8, height: 8)
        case .info:
            Circle().strokeBorder(severityColor, lineWidth: 2).frame(width: 8, height: 8)
        }
    }

    private var severityColor: Color {
        switch card.severity {
        case .warning: DGColor.danger
        case .notice: DGColor.warning
        case .info: DGColor.success
        }
    }

    static func severityWord(_ severity: CoachSeverity) -> String {
        switch severity {
        case .warning: "Warning"
        case .notice: "Notice"
        case .info: "Information"
        }
    }

    /// The evidence as one line, "e1RM 96 → 93 kg · weekly volume +18%" — each item is still
    /// its own VoiceOver element so the list reads "Volume: 120" then "Sets: 5".
    private var whyBox: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Why?")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DGColor.ink2)
            Text(card.evidence.map { "\($0.label) \(format($0.value))" }.joined(separator: " · "))
                .font(.system(size: 12.5))
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    card.evidence.map { "\($0.label): \(format($0.value))" }.joined(separator: ", ")
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(DGColor.ink1.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Informational cards (`.none`) get one button, not two. An "Approve" that did nothing but
    /// record agreement sat next to "Not now" looking like a choice with consequences and wasn't
    /// one; "Got it" says what the tap does.
    private var hasApprovableAction: Bool {
        if case .none = card.suggestedAction { return false }
        return true
    }

    private var actions: some View {
        HStack(spacing: DGSpace.s2) {
            if hasApprovableAction {
                Button(action: onApprove) {
                    Text(CoachCardCopy.primaryLabel(for: card.suggestedAction, formatWeight: formatWeight))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(DGColor.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel("Approve, \(card.title)")
            }
            Button(action: onDismiss) {
                Text(hasApprovableAction ? "Not now" : "Got it")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        DGColor.ink1.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Dismiss, \(card.title)")
        }
    }

    private func format(_ value: CoachEvidenceValue) -> String {
        switch value {
        case .count(let count): String(count)
        case .weightKg(let kg): formatWeight(kg)
        case .date(let date): Self.dateFormatter.string(from: date)
        case .number(let number):
            Self.numberFormatter.string(from: number as NSNumber) ?? String(format: "%.2f", number)
        case .text(let text): text
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    /// Plain decimal, not a percent: `.number` evidence covers both ratios (0…1, e.g. "Decline")
    /// and raw counts (e.g. fractional "sets in window" from secondary-muscle weighting), and
    /// only the label — not this formatter — knows which one a given item is.
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
