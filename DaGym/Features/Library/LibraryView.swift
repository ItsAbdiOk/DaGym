import GymCore
import SwiftData
import SwiftUI

/// Exercise Library — search, filter chips and a scrolling list of
/// exercises grouped under the active filter, driven by the store.
struct LibraryView: View {
    @Environment(WorkoutStore.self) private var store

    @State private var exercises: [ExerciseInfo] = []
    @State private var totalCount = 0
    @State private var searchText = ""
    @State private var selectedMuscle: Muscle?
    @State private var selectedEquipment: EquipmentOption?
    @State private var favoritesOnly = false
    @State private var customOnly = false
    @State private var showingNewExercise = false
    @State private var profile: EquipmentProfileInfo?
    @State private var showAllEquipment = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        if let profile, profile.restrictsLibrary {
                            EquipmentFilterBanner(profileName: profile.name, showingAll: $showAllEquipment)
                        }
                        muscleChipRow
                        equipmentChipRow
                        sectionLabel
                        rows
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s6)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New exercise", systemImage: "plus") { showingNewExercise = true }
                }
            }
            // Explicit placement: on iOS 27 a `.searchable` inside a plain `Tab` without a
            // placement no longer shows a field at all (the system reserves search for a
            // `role: .search` tab), which made the library unsearchable.
            .searchable(
                text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search \(totalCount) exercises"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .sheet(isPresented: $showingNewExercise) {
                NewExerciseSheet { _ in refresh() }
            }
            .task {
                totalCount = store.exercises().count
                profile = store.activeProfile()
                refresh()
            }
            .onChange(of: store.changeToken) { _, _ in
                totalCount = store.exercises().count
                profile = store.activeProfile()
                refresh()
            }
            .onChange(of: showAllEquipment) { _, _ in refresh() }
            .onChange(of: searchText) { _, _ in refresh() }
            .onChange(of: selectedMuscle) { _, _ in refresh() }
            .onChange(of: selectedEquipment) { _, _ in refresh() }
            .onChange(of: favoritesOnly) { _, _ in refresh() }
            .onChange(of: customOnly) { _, _ in refresh() }
        }
        .dgWarmHaptics()
    }

    private var muscleChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpace.s2) {
                DGChip(title: "All", selected: selectedMuscle == nil) { selectedMuscle = nil }
                ForEach(Muscle.allCases) { muscle in
                    DGChip(title: muscle.displayName, selected: selectedMuscle == muscle) {
                        selectedMuscle = selectedMuscle == muscle ? nil : muscle
                    }
                }
            }
        }
    }

    private var equipmentChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpace.s2) {
                ForEach(EquipmentOption.allCases) { option in
                    DGChip(title: option.title, selected: selectedEquipment == option) {
                        selectedEquipment = selectedEquipment == option ? nil : option
                    }
                }
                DGChip(title: "Favourites", selected: favoritesOnly) { favoritesOnly.toggle() }
                DGChip(title: "Custom", selected: customOnly) { customOnly.toggle() }
            }
        }
    }

    private var sectionLabel: some View {
        Text("\(sectionTitle) · \(exercises.count) exercises").dgLabel()
    }

    private var sectionTitle: String {
        selectedMuscle?.displayName.uppercased() ?? "ALL"
    }

    private var rows: some View {
        LazyVStack(spacing: DGSpace.s3) {
            ForEach(exercises) { exercise in
                NavigationLink(value: exercise) {
                    LibraryRow(exercise: exercise) { toggleFavorite(exercise.id) }
                }
                .buttonStyle(.dgCard)
            }
        }
        .navigationDestination(for: ExerciseInfo.self) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
    }

    private func refresh() {
        let all = store.exercises(
            matching: searchText, muscle: selectedMuscle, equipment: selectedEquipment?.rawValue,
            favoritesOnly: favoritesOnly, customOnly: customOnly
        )
        exercises = all.filter { exercise in
            showAllEquipment || activeEquipment?.contains(exercise.equipment) ?? true
        }
    }

    /// Nil (no filter) unless the active profile leaves some equipment out.
    private var activeEquipment: Set<String>? {
        guard let profile, profile.restrictsLibrary else { return nil }
        return Set(profile.availableEquipment)
    }

    private func toggleFavorite(_ id: UUID) {
        store.toggleFavorite(id: id)
        refresh()
    }
}

/// "Showing what's in Home · Show all" — the equipment-profile filter's one-line banner,
/// shared by the library and the exercise picker. Tapping the trailing word flips the filter.
struct EquipmentFilterBanner: View {
    var profileName: String
    @Binding var showingAll: Bool

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
                .accessibilityHidden(true)
            Text(showingAll ? "Showing all equipment" : "Showing what's in \(profileName)")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink2)
                .lineLimit(1)
            Text("·").font(DGFont.footnote).foregroundStyle(DGColor.ink4).accessibilityHidden(true)
            Button(showingAll ? "Only \(profileName)" : "Show all") { showingAll.toggle() }
                .buttonStyle(.dgControl)
                .font(DGFont.footnote.weight(.semibold))
                .foregroundStyle(DGColor.coralText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: 36)
        .dgGlass(.thin, radius: 12)
    }
}

/// One 72 pt row in the library list.
private struct LibraryRow: View {
    var exercise: ExerciseInfo
    var onToggleFavorite: () -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            HStack(spacing: DGSpace.s3) {
                thumbnail
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
                accessory
            }
            .accessibilityElement(children: .combine)
            favoriteButton
        }
        .frame(minHeight: 72)
        .dgCard(radius: 14, padding: 12)
    }

    private var thumbnail: some View {
        BodyMapView(
            side: BodyMapMuscleMapping.thumbnailSide(forPrimary: exercise.primary),
            intensity: exercise.hitMap
        )
            .padding(6)
            .frame(width: 44, height: 44)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    /// Every row can be (un)favourited from the list, whether or not it has a lift on record.
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: exercise.isFavorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(exercise.isFavorite ? DGColor.prGoldText : DGColor.ink4)
                .frame(width: 28, height: 28)
                .background(
                    exercise.isFavorite ? DGColor.prGold.opacity(0.18) : DGColor.surface2, in: Circle()
                )
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(exercise.isFavorite ? "Remove from favourites" : "Add to favourites")
    }

    @ViewBuilder
    private var accessory: some View {
        if let best = exercise.bestE1RM {
            VStack(alignment: .trailing, spacing: 2) {
                Text(preferences.formatWeight(kg: best))
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.prGoldText)
                Text("E1RM").dgLabel()
            }
        } else if exercise.loggingStyle == .weightedBodyweight {
            DGTag(text: "BW+", tint: DGColor.infoText, wash: DGColor.info.opacity(0.16))
        } else if exercise.isCustom {
            DGTag(text: "Mine", tint: DGColor.coralText, wash: DGColor.coralWash)
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        LibraryView()
            .environment(store)
            .environment(Preferences())
    }
}
