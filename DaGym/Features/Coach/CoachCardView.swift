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
            // Severity is the dot's colour *and* its shape: a triangle for a warning, a filled
            // circle for a notice, a ring for information — so it survives colour-blindness.
            severityGlyph
                .padding(.top, 6)
            Text(card.title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
            Spacer(minLength: DGSpace.s2)
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
        case .info: DGColor.info
        }
    }

    static func severityWord(_ severity: CoachSeverity) -> String {
        switch severity {
        case .warning: "Warning"
        case .notice: "Notice"
        case .info: "Information"
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
                // Not `aiVioletText`: that violet is the app's AI accent, and this screen's own
                // header says these checks are rule-based and nothing is sent anywhere.
                .foregroundStyle(DGColor.ink3)
            }
            .buttonStyle(.dgControl)
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
                        // One element per row, so the list reads "Volume: 120" then "Sets: 5"
                        // rather than one run-on sentence.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.label): \(format(item.value))")
                    }
                }
                .padding(DGSpace.s3)
                .background(
                    DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
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

    /// Informational cards (`.none`) get one button, not two. An "Approve" that did nothing but
    /// record agreement sat next to "Dismiss" looking like a choice with consequences and wasn't
    /// one; "Got it" says what the tap does.
    private var hasApprovableAction: Bool {
        if case .none = card.suggestedAction { return false }
        return true
    }

    private var actions: some View {
        HStack(spacing: DGSpace.s2) {
            Button(hasApprovableAction ? "Dismiss" : "Got it") { onDismiss() }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .foregroundStyle(DGColor.ink2)
                .padding(.horizontal, DGSpace.s3)
                .frame(minHeight: 36)
                .background(DGColor.surface3, in: Capsule())
                .accessibilityLabel("Dismiss, \(card.title)")
            if hasApprovableAction {
                Button("Approve") { onApprove() }
                    .buttonStyle(.dgControl)
                    .font(DGFont.condensedLabel(13))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .padding(.horizontal, DGSpace.s3)
                    .frame(minHeight: 36)
                    .background(DGColor.coral, in: Capsule())
                    .accessibilityLabel("Approve, \(card.title)")
            }
            Spacer()
        }
    }

    private func actionNoteText(for action: CoachSuggestedAction) -> String? {
        switch action {
        case .deloadExercise(let exerciseName, _, let toWeightKg):
            // Says exactly what is written, and nothing that isn't: the target weight changes,
            // the set count doesn't, and it takes effect the next time this lift comes up.
            return "Approve sets \(exerciseName)'s target weight to \(formatWeight(toWeightKg)) in "
                + "your plan, so that's what your next session starts from. Your set count and "
                + "rep targets don't change, and you can undo it."
        case .substituteExercise(_, _, let candidateName):
            return "Approve just records your decision — to make the swap, tap the set's swap "
                + "button next time you train it and pick \(candidateName)."
        case .addSession(let weekday):
            return "Approve just records your decision — add \(weekday.displayName) from Schedule."
        case .restMuscle(let muscle):
            return "Approve just records your decision — ease off \(muscle.displayName) yourself "
                + "for a day or two."
        case .easeBackIn(let loadFraction):
            let percent = Int((loadFraction * 100).rounded())
            return "Approve just records your decision — start your next session around "
                + "\(percent)% of your usual weight."
        case .addExercise, .replaceExercise, .changeRepRange, .changeProgressionRule, .moveRestDay:
            return reviewActionNoteText(for: action)
        case .none:
            return nil
        }
    }

    /// The training-review actions (`CoachReviewSection`): each one is applied for real by
    /// `WorkoutStore.applyReviewChange`, and each is undoable from the toast.
    private func reviewActionNoteText(for action: CoachSuggestedAction) -> String? {
        switch action {
        case .addExercise(_, let exerciseName):
            return "Approve adds \(exerciseName) (3 × 8) to the routine that already trains its "
                + "muscles most. You can undo it."
        case .replaceExercise(_, let exerciseName, _, let withName):
            return "Approve swaps \(exerciseName) for \(withName) in every routine that programmes "
                + "it. Progress on \(exerciseName) is kept. You can undo it."
        case .changeRepRange(_, let exerciseName, let low, let high):
            return "Approve sets \(exerciseName)'s working sets to \(low)–\(high) reps in your plan. "
                + "You can undo it."
        case .changeProgressionRule(_, let exerciseName, let rule):
            return "Approve puts \(exerciseName) on \(rule.displayName) progression. You can undo it."
        case .moveRestDay(let from, let to):
            return "Approve moves \(from.displayName)'s session to \(to.displayName) in your "
                + "schedule. You can undo it."
        case .deloadExercise, .substituteExercise, .addSession, .restMuscle, .easeBackIn, .none:
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
