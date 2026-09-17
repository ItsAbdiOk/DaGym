import GymCore
import SwiftUI

/// One `propose_*` result in the transcript: the draft's summary, its exercises/days behind a
/// disclosure, and Apply / Discard. The screen owns the state (`CoachDraftCardState`) and the
/// undo toast, so this view only reports taps. Mirrors `CoachCardView`'s shape so the two
/// coach surfaces read as one. With a second opinion on, `originLabel` says whose card this
/// is, `reviewStrip` carries the reviewer's verdict on the drafter's card, and `rationale` is
/// the reviewer's own paragraph above its alternative. Long-press offers Copy and a note per
/// exercise the drafter gave a reason; the screen writes the clipboard
/// (`CoachDraftDetail.copyText`), saves the note and shows the toast. On a routine or program
/// card `keepsReasoning` is the "Keep the coach's reasoning as the routine note" switch the
/// screen reads when Apply is tapped.
struct CoachDraftCard: View {
    var draft: CoachChatDraft
    var state: CoachDraftCardState
    var formatWeight: (Double) -> String
    var originLabel: String?
    var reviewStrip: CoachReviewCopy.Strip?
    var rationale: String?
    var onApply: () -> Void
    var onDiscard: () -> Void
    var onCopy: () -> Void = {}
    var saveTargets: [CoachChatSaveTarget] = []
    var onSave: (CoachChatSaveTarget) -> Void = { _ in }
    /// nil on cards that create no routine (schedule, deload, swap): no switch is drawn.
    var keepsReasoning: Binding<Bool>?

    @Environment(\.coachDraftCardsExpanded) private var expandsByDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil until the lifter taps Details; until then the environment says how the card starts.
    @State private var isExpanded: Bool?
    /// Rows whose reason is shown in full rather than clipped to two lines.
    @State private var openReasons: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            if let rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DGSpace.s3)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(DGColor.coral).frame(width: 2)
                    }
                    .accessibilityLabel("Reviewer's reasoning: \(rationale)")
                    .accessibilityIdentifier(A11yID.coachChatDraftRationale)
            }
            header
            if let reviewStrip {
                CoachDraftReviewStrip(strip: reviewStrip)
            }
            disclosure
            if let caption = state.caption {
                Text(caption)
                    .font(DGFont.condensedLabel(12))
                    .foregroundStyle(state == .applied ? DGColor.success : DGColor.ink4)
            } else {
                if let keepsReasoning {
                    reasoningToggle(keepsReasoning)
                }
                actions
            }
        }
        .dgCard(radius: 18, padding: 15)
        .contextMenu {
            CoachChatSaveMenu(targets: saveTargets, onCopy: onCopy, onSave: onSave)
        }
        .accessibilityIdentifier(A11yID.coachChatDraftCard)
    }

    /// "PROPOSAL" tag, then the kind and — with a second opinion on — whose card this is; the
    /// summary as the title and the counts under it, the way the prototype's proposal card reads.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("Proposal")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink3)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 18)
                    .background(
                        DGColor.ink1.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                Text(originLabel.map { "\(kindLabel) · \($0)" } ?? kindLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
                    .lineLimit(1)
                    .accessibilityIdentifier(originLabel == nil ? "" : A11yID.coachChatDraftOrigin)
            }
            Text(draft.summary)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            if let counts = countLine {
                Text(counts)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
                    .padding(.top, 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    /// "6 exercises · 23 sets" for a routine, "3 routines · 14 exercises" for a program.
    private var countLine: String? {
        switch draft {
        case .routine(let proposal):
            CoachDraftDetail.countLine(proposal)
        case .program(let proposal) where !proposal.usesTemplate:
            "\(proposal.routines.count) routines · "
                + "\(proposal.routines.reduce(0) { $0 + $1.exercises.count }) exercises"
        default:
            nil
        }
    }

    private var headerAccessibilityLabel: String {
        let base = "\(kindLabel): \(draft.summary)"
        return originLabel.map { "\($0). \(base)" } ?? base
    }

    private var showsDetails: Bool { isExpanded ?? expandsByDefault }

    private var sections: [CoachDraftDetail.Section] {
        CoachDraftDetail.sections(for: draft, formatWeight: formatWeight)
    }

    @ViewBuilder
    private var disclosure: some View {
        Button { isExpanded = !showsDetails } label: {
            HStack(spacing: DGSpace.s1) {
                Text(showsDetails ? "Hide details" : "Details")
                Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(DGFont.condensedLabel(12))
            .foregroundStyle(DGColor.ink3)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(showsDetails ? "Hide details" : "Show details")

        if showsDetails {
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                ForEach(sections) { section in
                    if let title = section.title {
                        sectionHeader(title, subtitle: section.subtitle, first: section.id == 0)
                    }
                    ForEach(section.rows) { row in
                        detailRow(row)
                    }
                }
                if case .routine(let proposal) = draft, let notes = proposal.notes, !notes.isEmpty {
                    Text(notes)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DGSpace.s1)
                }
            }
            .padding(DGSpace.s3)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
        }
    }

    /// One routine inside a program: its name as a heading with the counts beside it, and a
    /// little air above every heading but the first so the routines read as groups.
    private func sectionHeader(_ title: String, subtitle: String?, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
            Spacer(minLength: DGSpace.s2)
            if let subtitle {
                Text(subtitle)
                    .font(DGFont.caption)
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .padding(.top, first ? 0 : DGSpace.s3)
        .padding(.bottom, DGSpace.s1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }

    /// Title and set line on one row; the drafter's reason, when it gave one, under them in
    /// two lines that a tap opens out. The reason is its own VoiceOver element so the row
    /// stays short.
    @ViewBuilder
    private func detailRow(_ row: CoachDraftDetail.Row) -> some View {
        HStack(alignment: .top) {
            Text(row.title)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink1)
            Spacer(minLength: DGSpace.s2)
            if let detail = row.detail {
                Text(detail)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.detail.map { "\(row.title): \($0)" } ?? row.title)
        if let reason = row.reason {
            Button {
                withAnimation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion)) {
                    if !openReasons.insert(row.id).inserted { openReasons.remove(row.id) }
                }
            } label: {
                Text(reason)
                    .font(DGFont.caption)
                    .foregroundStyle(DGColor.ink4)
                    .multilineTextAlignment(.leading)
                    .lineLimit(openReasons.contains(row.id) ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.bottom, DGSpace.s1)
            .accessibilityLabel("Why \(row.title): \(reason)")
            .accessibilityIdentifier(A11yID.coachChatDraftReason)
        }
    }

    /// On by default: the reply that came with the card is worth more on the routine than in a
    /// chat the lifter will not reopen.
    private func reasoningToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text("Keep the coach's reasoning as the routine note")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink2)
        }
        .tint(DGColor.coral)
        .accessibilityIdentifier(A11yID.coachChatDraftKeepReasoning)
    }

    private var actions: some View {
        HStack(spacing: DGSpace.s2) {
            Button(action: onApply) {
                Text("Apply")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(DGColor.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.dgControl)
            .accessibilityIdentifier(A11yID.coachChatDraftApply)
            Button(action: onDiscard) {
                Text("Discard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        DGColor.ink1.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.dgControl)
            .accessibilityIdentifier(A11yID.coachChatDraftDiscard)
        }
    }

    private var kindLabel: String {
        switch draft {
        case .routine: "Proposed routine"
        case .program: "Proposed program"
        case .schedule: "Proposed schedule"
        case .deload: "Proposed deload"
        case .swap: "Proposed swap"
        }
    }
}

#Preview {
    let routine = RoutineProposal(
        name: "Upper A",
        exercises: [
            CoachChatExerciseSpec(
                exerciseName: "Bench Press",
                sets: Array(repeating: CoachChatSetSpec(targetReps: 8, targetWeightKg: 60), count: 3),
                reason: "Your strongest press: 60 kg for 8 on 12 Sep, so it leads the session."
            ),
            CoachChatExerciseSpec(exerciseName: "Lat Pulldown", sets: [CoachChatSetSpec(targetReps: 12)])
        ],
        notes: "Rest two minutes between bench sets."
    )
    return VStack(spacing: DGSpace.s3) {
        CoachDraftCard(
            draft: .routine(routine), state: .proposed, formatWeight: { "\(Int($0)) kg" },
            originLabel: "Gemini's proposal",
            reviewStrip: .agreed(
                title: "Opus agrees", reasons: ["Volume matches your last four weeks", "Bench load is right"],
                confidence: "High confidence"
            ),
            onApply: {}, onDiscard: {}
        )
        CoachDraftCard(
            draft: .routine(routine), state: .notChosen, formatWeight: { "\(Int($0)) kg" },
            originLabel: "Opus's version", rationale: "Swapped the pulldown for a row: your lats are behind.",
            onApply: {}, onDiscard: {}
        )
    }
    .padding()
    .background(AmbientWash())
}

extension EnvironmentValues {
    /// Whether draft cards open with their rows showing. Off in the app — the card leads with
    /// its summary and Apply — and on for the screenshot build, whose shot is the rows and
    /// their reasons.
    @Entry var coachDraftCardsExpanded = false
}
