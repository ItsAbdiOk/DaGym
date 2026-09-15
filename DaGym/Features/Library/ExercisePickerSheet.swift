import GymCore
import SwiftData
import SwiftUI

/// Sheet for picking an exercise to add to a routine or swap into a
/// workout: search + muscle chips over the live library, dismisses after
/// a pick. Glass-thick, radius 32, detent `.large`.
struct ExercisePickerSheet: View {
    var onPick: (ExerciseInfo) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [ExerciseInfo] = []
    @State private var searchText = ""
    @State private var selectedMuscle: Muscle?
    @State private var profile: EquipmentProfileInfo?
    @State private var showAllEquipment = false
    @State private var hidden = HiddenCounts()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                VStack(alignment: .leading, spacing: DGSpace.s4) {
                    if let profile, profile.restrictsLibrary {
                        EquipmentFilterBanner(
                            profileName: profile.name, hidden: hidden, showingAll: $showAllEquipment
                        )
                    }
                    chipRow
                    rows
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
        .presentationCornerRadius(DGRadius.sheet)
        .task {
            profile = store.activeProfile()
            refresh()
        }
        .onChange(of: searchText) { _, _ in refresh() }
        .onChange(of: selectedMuscle) { _, _ in refresh() }
        .onChange(of: showAllEquipment) { _, _ in refresh() }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpace.s2) {
                ForEach(Muscle.allCases) { muscle in
                    DGChip(title: muscle.displayName, selected: selectedMuscle == muscle) {
                        selectedMuscle = selectedMuscle == muscle ? nil : muscle
                    }
                }
            }
        }
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: DGSpace.s3) {
                ForEach(exercises) { exercise in
                    Button {
                        onPick(exercise)
                        dismiss()
                    } label: {
                        ExercisePickerRow(exercise: exercise)
                    }
                    .buttonStyle(.dgCard)
                }
            }
            .padding(.bottom, DGSpace.s6)
        }
    }

    private func refresh() {
        let all = store.exercises(matching: searchText, muscle: selectedMuscle)
        guard let profile, profile.restrictsLibrary else {
            exercises = all
            return
        }
        exercises = ExercisePickerFilter.visible(
            all, availability: profile.availability, showingAll: showAllEquipment, hidden: &hidden
        )
    }
}

/// The picker's profile filter as a pure function: what stays, and how many rows the profile
/// hides (counted even while "Show all" is on, so the banner keeps its numbers).
enum ExercisePickerFilter {
    static func visible(
        _ exercises: [ExerciseInfo], availability: EquipmentAvailability, showingAll: Bool,
        hidden: inout HiddenCounts
    ) -> [ExerciseInfo] {
        hidden = availability.hiddenCounts(of: exercises.map { ($0.equipment, $0.machine) })
        guard !showingAll else { return exercises }
        return exercises.filter { availability.allows(equipment: $0.equipment, machine: $0.machine) }
    }
}

/// Compact copy of `LibraryView`'s row, sized for the picker sheet.
private struct ExercisePickerRow: View {
    var exercise: ExerciseInfo

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            BodyMapView(
                side: BodyMapMuscleMapping.thumbnailSide(forPrimary: exercise.primary),
                intensity: exercise.hitMap
            )
                .padding(6)
                .frame(width: 44, height: 44)
                .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(1)
                Text(exercise.muscleLine)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .lineLimit(1)
            }
            Spacer()
            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 72)
        .dgCard(radius: 14, padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(exercise.isFavorite ? "\(exercise.name), favourite" : exercise.name)
        .accessibilityValue(exercise.muscleLine)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                ExercisePickerSheet(onPick: { _ in })
                    .environment(WorkoutStore(context: container.mainContext))
            }
    } else {
        Text("Preview unavailable")
    }
}
