import GymCore
import SwiftUI

/// One `propose_*` result in the transcript: the draft's summary, its exercises/days behind a
/// disclosure, and Apply / Discard. The screen owns the state (`CoachDraftCardState`) and the
/// undo toast, so this view only reports taps. Mirrors `CoachCardView`'s shape so the two
/// coach surfaces read as one. With a second opinion on, `originLabel` says whose card this
/// is, `reviewStrip` carries the reviewer's verdict on the drafter's card, and `rationale` is
/// the reviewer's own paragraph above its alternative. Long-press offers Copy; the screen
/// writes the clipboard (`CoachDraftDetail.copyText`) and shows the toast.
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

    @Environment(\.coachDraftCardsExpanded) private var expandsByDefault
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
                        RoundedRectangle(cornerRadius: 1).fill(DGColor.aiViolet).frame(width: 2)
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
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(state == .applied ? DGColor.success : DGColor.ink4)
            } else {
                actions
            }
        }
        .dgCard(padding: DGSpace.s4)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc", action: onCopy)
        }
        .accessibilityIdentifier(A11yID.coachChatDraftCard)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DGSpace.s2) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.aiVioletText)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                HStack(spacing: DGSpace.s2) {
                    Text(kindLabel)
                        .font(DGFont.condensedLabel(11))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink4)
                    if let originLabel {
                        Text(originLabel)
                            .font(DGFont.condensedLabel(11))
                            .tracking(1.0)
                            .textCase(.uppercase)
                            .foregroundStyle(DGColor.aiVioletText)
                            .padding(.horizontal, DGSpace.s2)
                            .frame(minHeight: 18)
                            .background(Capsule().fill(DGColor.surface2))
                            .accessibilityIdentifier(A11yID.coachChatDraftOrigin)
                    }
                }
                Text(draft.summary)
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DGSpace.s2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    private var headerAccessibilityLabel: String {
        let base = "\(kindLabel): \(draft.summary)"
        return originLabel.map { "\($0). \(base)" } ?? base
    }

    private var showsDetails: Bool { isExpanded ?? expandsByDefault }

    private var rows: [CoachDraftDetail.Row] { CoachDraftDetail.rows(for: draft, formatWeight: formatWeight) }

    @ViewBuilder
    private var disclosure: some View {
        Button { isExpanded = !showsDetails } label: {
            HStack(spacing: DGSpace.s1) {
                Text(showsDetails ? "Hide details" : "Details")
                Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(DGFont.condensedLabel(12))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(DGColor.ink3)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(showsDetails ? "Hide details" : "Show details")

        if showsDetails {
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                ForEach(rows) { row in
                    detailRow(row)
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
                withAnimation(DGMotion.standard) {
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

    private var actions: some View {
        HStack(spacing: DGSpace.s3) {
            Button(action: onApply) {
                Text("Apply")
                    .font(DGFont.condensedLabel(13))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.inkOnCoral)
                    .padding(.horizontal, DGSpace.s4)
                    .frame(minHeight: DGTap.min)
                    .background(DGColor.coral, in: Capsule())
            }
            .buttonStyle(.dgControl)
            .accessibilityIdentifier(A11yID.coachChatDraftApply)
            Button(action: onDiscard) {
                Text("Discard")
                    .font(DGFont.condensedLabel(13))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink2)
                    .padding(.horizontal, DGSpace.s4)
                    .frame(minHeight: DGTap.min)
            }
            .buttonStyle(.dgControl)
            .accessibilityIdentifier(A11yID.coachChatDraftDiscard)
            Spacer()
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

    private var symbol: String {
        switch draft {
        case .routine: "list.bullet.rectangle"
        case .program: "calendar.badge.plus"
        case .schedule: "calendar"
        case .deload: "arrow.down.right"
        case .swap: "arrow.left.arrow.right"
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
