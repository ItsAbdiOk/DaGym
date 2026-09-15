import GymCore
import SwiftUI

/// Mid-workout swap: pick a reason (or type one), see why the coach chose these three, then
/// swap. See mockup 10_01 (left). Candidates always come from the rule engine
/// (`WorkoutStore.scoredSubstitutes`, plan §6.6); when the on-device coach is available it
/// reorders those same three for the reason in the lifter's own words and explains each — it
/// can never add an exercise (`SubstitutionRankingValidator`).
struct SwapExerciseSheet: View {
    var exercise: ExerciseInfo
    /// Sets already ticked on this entry. Above zero the swap keeps them and adds the candidate
    /// after the entry, so the sheet confirms first (and, in a superset, asks where it goes).
    var loggedSetCount = 0
    var isInSuperset = false
    /// `(candidate, keepInSuperset)` — the flag only matters for a grouped entry with logged sets.
    var onPick: (ExerciseInfo, Bool) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(CoachServices.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @State private var reason = SwapReason.machineTaken
    @State private var reasonText = ""
    @State private var suggestions: [SubstitutionSuggestion] = []
    @State private var isRanking = false
    @State private var showingLibrary = false
    @State private var pendingCandidate: ExerciseInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            Text("Swap \(exercise.name)")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            reasonChips
            reasonField
            WhyCard(title: isRanking ? "Ordering for your reason…" : "Why these three", message: whyMessage)
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
        .presentationDetents([.height(640)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
        .task(id: reason) { await refresh() }
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

    /// Free text on top of the chips: "left knee's twinging", "only dumbbells free". A typed
    /// reason that maps onto a chip (`SwapReasonParser`) picks that chip, so the rule engine
    /// filters correctly; the on-device coach then reads the words themselves.
    private var reasonField: some View {
        TextField("Or say why in your own words", text: $reasonText)
            .font(DGFont.body)
            .foregroundStyle(DGColor.ink1)
            .padding(.horizontal, DGSpace.s4)
            .frame(minHeight: 44)
            .dgCard(padding: 0)
            .submitLabel(.done)
            .onSubmit {
                if let parsed = SwapReasonParser.parse(reasonText), parsed != reason {
                    reason = parsed
                } else {
                    Task { await refresh() }
                }
            }
            .accessibilityLabel("Reason for the swap, in your own words")
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

    /// Rule candidates first (instant), then the model's ordering of those same candidates
    /// when it's available — on any failure the rule order simply stays.
    private func refresh() async {
        let scored = store.scoredSubstitutes(for: exercise.id, reason: reason)
        suggestions = store.suggestions(from: SubstitutionRankingValidator.ruleOrder(scored))
        guard coach.isUsingLanguageModel, !scored.isEmpty,
              let subject = store.fetchExerciseModel(id: exercise.id).map(store.substitutionCandidate(for:))
        else { return }
        isRanking = true
        defer { isRanking = false }
        let words = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        let described = words.isEmpty ? FlowChips.title(for: reason) : words
        if let ranked = try? await coach.model.rankSubstitutes(
            for: subject, reason: described, candidates: scored, recoveryMap: store.recoverySnapshot().map
        ), !Task.isCancelled {
            suggestions = store.suggestions(from: ranked)
        }
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

    static func title(for reason: SwapReason) -> String {
        options.first { $0.reason == reason }?.title ?? "No reason given"
    }

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
                .accessibilityHidden(true)
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
                .frame(minHeight: 36)
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
                .environment(CoachServices.make(preferences: Preferences()))
        )
    }
    return AnyView(EmptyView())
}
