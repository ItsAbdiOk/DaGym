import GymCore
import SwiftData
import SwiftUI

/// Equipment filter / picker options shared with `NewExerciseSheet`.
enum EquipmentOption: String, CaseIterable, Identifiable {
    case barbell, dumbbell, bodyweight, cable, machine, kettlebell, bands, ezBar, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .bodyweight: "Bodyweight"
        case .cable: "Cable"
        case .machine: "Machine"
        case .kettlebell: "Kettlebell"
        case .bands: "Bands"
        case .ezBar: "EZ Bar"
        case .other: "Other"
        }
    }
}

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

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        header
                        searchField
                        muscleChipRow
                        equipmentChipRow
                        sectionLabel
                        rows
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewExercise) {
                NewExerciseSheet { _ in refresh() }
            }
            .task { refresh() }
            .onChange(of: searchText) { _, _ in refresh() }
            .onChange(of: selectedMuscle) { _, _ in refresh() }
            .onChange(of: selectedEquipment) { _, _ in refresh() }
            .onChange(of: favoritesOnly) { _, _ in refresh() }
            .onChange(of: customOnly) { _, _ in refresh() }
        }
    }

    private var header: some View {
        HStack {
            Text("Library")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "plus") { showingNewExercise = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
            TextField("Search \(totalCount) exercises", text: $searchText)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(height: 48)
        .dgGlass(.thin, radius: 14)
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
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: ExerciseInfo.self) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
    }

    private func refresh() {
        exercises = store.exercises(
            matching: searchText, muscle: selectedMuscle, equipment: selectedEquipment?.rawValue,
            favoritesOnly: favoritesOnly, customOnly: customOnly
        )
        totalCount = store.exercises().count
    }

    private func toggleFavorite(_ id: UUID) {
        store.toggleFavorite(id: id)
        refresh()
    }
}

/// One 72 pt row in the library list.
private struct LibraryRow: View {
    var exercise: ExerciseInfo
    var onToggleFavorite: () -> Void

    var body: some View {
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
        .frame(height: 72)
        .dgCard(radius: 14, padding: 12)
    }

    private var thumbnail: some View {
        BodyMapView(side: .front, intensity: exercise.hitMap)
            .padding(6)
            .frame(width: 44, height: 44)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var accessory: some View {
        if let best = exercise.bestE1RM {
            VStack(alignment: .trailing, spacing: 2) {
                Text(WorkoutSession.format(best))
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.prGoldText)
                Text("E1RM").dgLabel()
            }
        } else if exercise.isFavorite {
            Button(action: onToggleFavorite) {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.prGoldText)
                    .frame(width: 28, height: 28)
                    .background(DGColor.prGold.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
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
    }
}
