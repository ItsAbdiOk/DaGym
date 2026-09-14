import GymCore
import SwiftUI

/// One `CoachCard`: severity, title, one-sentence body, evidence collapsed behind a "Why"
/// disclosure, and Approve/Dismiss. See `CoachView` for the screen this tiles into.
struct CoachCardView: View {
    var card: CoachCard
    var isExpanded: Bool
    var formatWeight: (Double) -> String
    var onToggle: () -> Void
    var onApprove: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            header
            Text(card.body)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            whyDisclosure
            actionNote
            actions
        }
        .dgCard(padding: DGSpace.s4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DGSpace.s2) {
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(card.title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
            Spacer(minLength: DGSpace.s2)
        }
    }

    private var severityColor: Color {
        switch card.severity {
        case .warning: DGColor.danger
        case .notice: DGColor.warning
        case .info: DGColor.info
        }
    }

    @ViewBuilder
    private var whyDisclosure: some View {
        if !card.evidence.isEmpty {
            Button(action: onToggle) {
                HStack(spacing: DGSpace.s1) {
                    Text(isExpanded ? "Hide why" : "Why?")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(DGFont.condensedLabel(12))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.aiVioletText)
            }
            .buttonStyle(.dgControl)
            .dgTapTarget()
            .accessibilityLabel(isExpanded ? "Hide evidence" : "Show evidence")

            if isExpanded {
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    ForEach(Array(card.evidence.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.label)
                                .font(DGFont.footnote)
                                .foregroundStyle(DGColor.ink3)
                            Spacer(minLength: DGSpace.s2)
                            Text(format(item.value))
                                .font(DGFont.footnote)
                                .foregroundStyle(DGColor.ink1)
                        }
                    }
                }
                .padding(DGSpace.s3)
                .background(
                    DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// What Approve actually does for this card's suggested action — honest either way: a deload
    /// is applied for real, everything else is recorded but left for the lifter to act on
    /// themselves (see `CoachView.approve(_:)`).
    @ViewBuilder
    private var actionNote: some View {
        if let note = actionNoteText(for: card.suggestedAction) {
            Text(note)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var actions: some View {
        HStack(spacing: DGSpace.s2) {
            Button("Dismiss") { onDismiss() }
                .buttonStyle(.dgControl)
                .dgTapTarget()
                .font(DGFont.condensedLabel(13))
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink2)
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 36)
                .background(DGColor.surface3, in: Capsule())
                .accessibilityLabel("Dismiss, \(card.title)")
            Button("Approve") { onApprove() }
                .buttonStyle(.dgControl)
                .dgTapTarget()
                .font(DGFont.condensedLabel(13))
                .textCase(.uppercase)
                .foregroundStyle(DGColor.inkOnCoral)
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 36)
                .background(DGColor.coral, in: Capsule())
                .accessibilityLabel("Approve, \(card.title)")
            Spacer()
        }
    }

    private func actionNoteText(for action: CoachSuggestedAction) -> String? {
        switch action {
        case .deloadExercise(_, let toWeightKg, let sets):
            return "Approve applies this: your plan updates to \(sets) sets at \(formatWeight(toWeightKg))."
        case .substituteExercise(_, _, let candidateName):
            return "Approve just records your decision — swap in \(candidateName) from the set's "
                + "swap button next time you train it."
        case .addSession(let weekday):
            return "Approve just records your decision — add \(weekday.displayName) from Schedule."
        case .restMuscle(let muscle):
            return "Approve just records your decision — ease off \(muscle.displayName) yourself "
                + "for a day or two."
        case .easeBackIn(let loadFraction):
            let percent = Int((loadFraction * 100).rounded())
            return "Approve just records your decision — start your next session around "
                + "\(percent)% of your usual weight."
        case .none:
            return nil
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
