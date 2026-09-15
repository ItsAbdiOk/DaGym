import GymCore
import SwiftUI

/// One `propose_*` result in the transcript: the draft's summary, its exercises/days behind a
/// disclosure, and Apply / Discard. The screen owns the state (`CoachDraftCardState`) and the
/// undo toast, so this view only reports taps. Mirrors `CoachCardView`'s shape so the two
/// coach surfaces read as one.
struct CoachDraftCard: View {
    var draft: CoachChatDraft
    var state: CoachDraftCardState
    var formatWeight: (Double) -> String
    var onApply: () -> Void
    var onDiscard: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            header
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
                Text(kindLabel)
                    .font(DGFont.condensedLabel(11))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink4)
                Text(draft.summary)
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DGSpace.s2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kindLabel): \(draft.summary)")
    }

    private var rows: [CoachDraftDetail.Row] { CoachDraftDetail.rows(for: draft, formatWeight: formatWeight) }

    @ViewBuilder
    private var disclosure: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: DGSpace.s1) {
                Text(isExpanded ? "Hide details" : "Details")
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(DGFont.condensedLabel(12))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(DGColor.ink3)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(isExpanded ? "Hide details" : "Show details")

        if isExpanded {
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                ForEach(rows) { row in
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
                sets: Array(repeating: CoachChatSetSpec(targetReps: 8, targetWeightKg: 60), count: 3)
            ),
            CoachChatExerciseSpec(exerciseName: "Lat Pulldown", sets: [CoachChatSetSpec(targetReps: 12)])
        ],
        notes: "Rest two minutes between bench sets."
    )
    return CoachDraftCard(
        draft: .routine(routine), state: .proposed, formatWeight: { "\(Int($0)) kg" },
        onApply: {}, onDiscard: {}
    )
    .padding()
    .background(AmbientWash())
}
