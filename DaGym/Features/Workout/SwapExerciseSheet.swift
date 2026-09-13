import GymCore
import SwiftUI

/// Mid-workout swap: pick a reason, see why the coach chose these three,
/// then swap. See mockup 10_01 (left).
struct SwapExerciseSheet: View {
    var exercise: ExerciseInfo
    var onPick: (ExerciseInfo) -> Void

    @State private var reason = Reason.machineTaken
    @Environment(\.dismiss) private var dismiss

    private let candidates = [SampleData.inclineDB, SampleData.deficitPushup, SampleData.weightedDip]

    fileprivate enum Reason: String, CaseIterable {
        case machineTaken = "Machine taken"
        case noBarbell = "No barbell"
        case shoulderHurts = "Shoulder hurts"
        case shortOnTime = "Short on time"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            Text("Swap \(exercise.name)")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            reasonChips
            WhyCard(
                title: "Why these three",
                message: "All three hit "
                    + "\(exercise.primary.first?.displayName.lowercased() ?? "the same muscle") "
                    + "as the prime mover with the same set count, and none needs the "
                    + "\(exercise.equipment.lowercased()) station."
            )
            VStack(spacing: DGSpace.s2) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    CandidateRow(exercise: candidate, isPrimary: index == 0) {
                        onPick(candidate)
                        dismiss()
                    }
                }
            }
            Button("Search the library instead") {}
                .buttonStyle(.plain)
                .font(DGFont.condensedLabel(13))
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink3)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s5)
        .padding(.bottom, DGSpace.s4)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
    }

    private var reasonChips: some View {
        FlowChips(reason: $reason)
    }
}

/// Reason chips wrap onto a second line, matching the mockup's two-row layout.
private struct FlowChips: View {
    @Binding var reason: SwapExerciseSheet.Reason

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: DGSpace.s2)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: DGSpace.s2) {
            ForEach(SwapExerciseSheet.Reason.allCases, id: \.self) { option in
                DGChip(
                    title: option.rawValue, selected: reason == option,
                    selectedFill: DGColor.aiViolet, selectedInk: .white
                ) {
                    reason = option
                }
            }
        }
    }
}

private struct CandidateRow: View {
    var exercise: ExerciseInfo
    var isPrimary: Bool
    var onUse: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            BodyMapView(side: .front, mode: .hit, intensity: exercise.hitMap)
                .padding(6)
                .frame(width: 40, height: 40)
                .background(
                    DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name.uppercased())
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
                Text(footnote)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer(minLength: DGSpace.s2)
            Button("Use", action: onUse)
                .buttonStyle(.plain)
                .font(DGFont.condensedLabel(12))
                .textCase(.uppercase)
                .foregroundStyle(isPrimary ? .white : DGColor.ink2)
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 36)
                .background(isPrimary ? DGColor.aiViolet : DGColor.surface3, in: Capsule())
        }
        .dgCard(padding: DGSpace.s3)
    }

    private var footnote: String {
        exercise.equipment + (exercise.sessions > 0 ? " · \(exercise.sessions) sessions logged" : " · new")
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SwapExerciseSheet(exercise: SampleData.cableFly, onPick: { _ in })
        }
}
