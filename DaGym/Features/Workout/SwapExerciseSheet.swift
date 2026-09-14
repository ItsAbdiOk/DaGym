import GymCore
import SwiftUI

/// Mid-workout swap: pick a reason, see why the coach chose these three,
/// then swap. See mockup 10_01 (left). Suggestions come from
/// `WorkoutStore.substitutes(for:reason:)` (plan §6.6, rule-based).
struct SwapExerciseSheet: View {
    var exercise: ExerciseInfo
    /// Sets already ticked on this entry. Above zero the swap keeps them and adds the candidate
    /// after the entry, so the sheet confirms first (and, in a superset, asks where it goes).
    var loggedSetCount = 0
    var isInSuperset = false
    /// `(candidate, keepInSuperset)` — the flag only matters for a grouped entry with logged sets.
    var onPick: (ExerciseInfo, Bool) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason = SwapReason.machineTaken
    @State private var suggestions: [SubstitutionSuggestion] = []
    @State private var showingLibrary = false
    @State private var pendingCandidate: ExerciseInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            Text("Swap \(exercise.name)")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            reasonChips
            WhyCard(title: "Why these three", message: whyMessage)
            candidateList
            Button("Search the library instead") { showingLibrary = true }
                .buttonStyle(.dgControl)
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
        .task(id: reason) { refresh() }
        .sheet(isPresented: $showingLibrary) {
            ExercisePickerSheet(onPick: use)
        }
        .confirmationDialog(
            "Keep \(loggedSetCount) logged \(loggedSetCount == 1 ? "set" : "sets")?",
            isPresented: pendingIsPresented, titleVisibility: .visible, presenting: pendingCandidate
        ) { candidate in
            if isInSuperset {
                Button("Add \(candidate.name) to the superset") {
                    confirm(candidate, keepInSuperset: true)
                }
                Button("Add \(candidate.name) after the superset") {
                    confirm(candidate, keepInSuperset: false)
                }
            } else {
                Button("Add \(candidate.name)") { confirm(candidate, keepInSuperset: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { candidate in
            Text("\(exercise.name) stays with what you've logged; \(candidate.name) is added after it.")
        }
    }

    private var pendingIsPresented: Binding<Bool> {
        Binding(get: { pendingCandidate != nil }, set: { if !$0 { pendingCandidate = nil } })
    }

    private var reasonChips: some View {
        FlowChips(reason: $reason)
    }

    @ViewBuilder
    private var candidateList: some View {
        if suggestions.isEmpty {
            EmptyState(
                symbol: "arrow.triangle.2.circlepath",
                title: "Nothing Fits Yet",
                message: "No exercise in your library matches this reason and equipment. "
                    + "Search the library instead."
            )
        } else {
            VStack(spacing: DGSpace.s2) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    CandidateRow(suggestion: suggestion, isPrimary: index == 0, onUse: use)
                }
            }
        }
    }

    /// The lead suggestion's "why", or a fallback when nothing qualified.
    private var whyMessage: String {
        suggestions.first?.why
            ?? "Nothing in your equipment matches \(exercise.name) for this reason yet — "
                + "try the library instead."
    }

    private func refresh() {
        suggestions = store.substitutes(for: exercise.id, reason: reason)
    }

    private func use(_ candidate: ExerciseInfo) {
        if loggedSetCount > 0 {
            pendingCandidate = candidate
        } else {
            confirm(candidate, keepInSuperset: false)
        }
    }

    private func confirm(_ candidate: ExerciseInfo, keepInSuperset: Bool) {
        onPick(candidate, keepInSuperset)
        dismiss()
    }
}

/// Reason chips wrap onto a second line, matching the mockup's two-row layout.
private struct FlowChips: View {
    @Binding var reason: SwapReason

    private static let options: [(reason: SwapReason, title: String)] = [
        (.machineTaken, "Machine taken"),
        (.noBarbell, "No barbell"),
        (.shoulderHurts, "Shoulder hurts"),
        (.shortOnTime, "Short on time"),
        // The Coach's struggling-exercise card tells the lifter to swap from here, so the reason
        // it scored its suggestion with has to be one they can actually pick.
        (.strugglingWithExercise, "Struggling with it")
    ]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: DGSpace.s2)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: DGSpace.s2) {
            ForEach(Array(Self.options.enumerated()), id: \.offset) { _, option in
                DGChip(
                    title: option.title, selected: reason == option.reason,
                    selectedFill: DGColor.aiViolet, selectedInk: .white
                ) {
                    reason = option.reason
                }
            }
        }
    }
}

private struct CandidateRow: View {
    var suggestion: SubstitutionSuggestion
    var isPrimary: Bool
    var onUse: (ExerciseInfo) -> Void

    private var exercise: ExerciseInfo { suggestion.exercise }

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            BodyMapView(
                side: BodyMapMuscleMapping.thumbnailSide(forPrimary: exercise.primary),
                mode: .hit,
                intensity: exercise.hitMap
            )
                .padding(6)
                .frame(width: 40, height: 40)
                .background(
                    DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name.uppercased())
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
                Text(suggestion.why)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer(minLength: DGSpace.s2)
            Button("Use") { onUse(exercise) }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(12))
                .textCase(.uppercase)
                .foregroundStyle(isPrimary ? .white : DGColor.ink2)
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 36)
                .background(isPrimary ? DGColor.aiViolet : DGColor.surface3, in: Capsule())
        }
        .dgCard(padding: DGSpace.s3)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            Color.clear
                .sheet(isPresented: .constant(true)) {
                    SwapExerciseSheet(exercise: SampleData.cableFly, onPick: { _, _ in })
                }
                .environment(store)
        )
    }
    return AnyView(EmptyView())
}
