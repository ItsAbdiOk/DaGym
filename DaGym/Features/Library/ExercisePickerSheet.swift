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

    var body: some View {
        ZStack {
            AmbientWash()
            VStack(alignment: .leading, spacing: DGSpace.s4) {
                header
                searchField
                if let profile, profile.restrictsLibrary {
                    EquipmentFilterBanner(profileName: profile.name, showingAll: $showAllEquipment)
                }
                chipRow
                rows
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s3)
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

    private var header: some View {
        HStack {
            Text("Add Exercise")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .dgLabel()
        }
    }

    private var searchField: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
            TextField("Search exercises", text: $searchText)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(height: 48)
        .dgGlass(.thin, radius: 14)
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, DGSpace.s6)
        }
    }

    private func refresh() {
        let all = store.exercises(matching: searchText, muscle: selectedMuscle)
        guard let profile, profile.restrictsLibrary, !showAllEquipment else {
            exercises = all
            return
        }
        let available = Set(profile.availableEquipment)
        exercises = all.filter { available.contains($0.equipment) }
    }
}

/// Compact copy of `LibraryView`'s row, sized for the picker sheet.
private struct ExercisePickerRow: View {
    var exercise: ExerciseInfo

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            BodyMapView(side: .front, intensity: exercise.hitMap)
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
