import GymCore
import SwiftData
import SwiftUI
import os

private let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

/// Exercise Library — search, filter chips and a scrolling list of
/// exercises grouped under the active filter, driven by the store.
struct LibraryView: View {
    @Environment(WorkoutStore.self) private var store

    /// The live library, read once per store change. Every search keystroke and chip tap is an
    /// in-memory filter over this rather than a fresh two-fetch catalogue build (~60 ms on a
    /// Low Power Mode debug build, on the main thread, per key).
    @State private var catalogue: WorkoutStore.ExerciseCatalogue?
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
    @State private var hidden = HiddenCounts()
    /// Which chips still find a row, recomputed with every `refresh()` (so debounced with the
    /// search text) from the same catalogue pass — never a fetch per chip.
    @State private var facets = LibraryFacets.Remaining()
    @State private var showingMuscleMap = false
    /// On (the default, and the chips' long-standing behaviour) a muscle filter matches rows
    /// that work the muscle as a secondary mover too; the "by muscle" card exposes the switch.
    @State private var includeSecondary = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The results label's scroll anchor for a body-map tap.
    private static let resultsAnchor = "library.results"

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        if let profile, profile.restrictsLibrary {
                            EquipmentFilterBanner(
                                profileName: profile.name, hidden: hidden, showingAll: $showAllEquipment
                            )
                        }
                        byMuscleButton
                        if showingMuscleMap {
                            LibraryMuscleMapCard(
                                counts: facets.muscleCounts, selected: selectedMuscle,
                                includeSecondary: $includeSecondary
                            ) { muscle in select(muscle, scrolling: proxy) }
                        }
                        muscleChipRow
                        equipmentChipRow
                        sectionLabel.id(Self.resultsAnchor)
                        rows
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s6)
                }
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New exercise", systemImage: "plus") { showingNewExercise = true }
            }
        }
        .searchable(
            text: $searchText, placement: searchPlacement, prompt: "Search \(totalCount) exercises"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .sheet(isPresented: $showingNewExercise) {
            NewExerciseSheet { _ in refresh() }
        }
        .task { reload() }
        .refreshOnStoreChange(reload)
        .onChange(of: showAllEquipment) { _, _ in refresh() }
        // Debounced: a fast typist's intermediate strings are never filtered at all.
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            refresh()
        }
        .onChange(of: selectedMuscle) { _, _ in refresh() }
        .onChange(of: selectedEquipment) { _, _ in refresh() }
        .onChange(of: favoritesOnly) { _, _ in refresh() }
        .onChange(of: customOnly) { _, _ in refresh() }
        .onChange(of: includeSecondary) { _, _ in refresh() }
        .dgWarmHaptics()
    }

    /// A body-map tap is the muscle chip's tap plus a scroll to the results, so the list the
    /// tap just filtered is on screen; the card stays open for the next region.
    private func select(_ muscle: Muscle, scrolling proxy: ScrollViewProxy) {
        selectedMuscle = muscle
        withAnimation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion)) {
            proxy.scrollTo(Self.resultsAnchor, anchor: .top)
        }
    }

    /// Opens the body-map card; the same glass strip as the profile banner so it reads as a
    /// filter control, not a row.
    private var byMuscleButton: some View {
        Button {
            withAnimation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion)) {
                showingMuscleMap.toggle()
            }
        } label: {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Explore by muscle")
                    .font(DGFont.condensedLabel(14))
                Spacer()
                Image(systemName: showingMuscleMap ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DGColor.ink2)
            .padding(.horizontal, DGSpace.s3)
            .frame(minHeight: 44)
            .dgGlass(.thin, radius: 12)
        }
        .buttonStyle(.dgCard)
        .accessibilityIdentifier(A11yID.libraryByMuscle)
        .accessibilityAddTraits(showingMuscleMap ? .isSelected : [])
        .accessibilityHint(showingMuscleMap ? "Hides the body map" : "Shows a body map to pick a muscle from")
    }

    /// A chip that would find nothing under every *other* filter is dimmed and disabled; the
    /// selected one stays live so one tap clears it (`facets` is refreshed with the rows).
    private var muscleChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpace.s2) {
                DGChip(title: "All", selected: selectedMuscle == nil) { selectedMuscle = nil }
                ForEach(Muscle.allCases) { muscle in
                    DGChip(
                        title: muscle.displayName, selected: selectedMuscle == muscle,
                        isEmpty: !facets.muscles.contains(muscle)
                    ) {
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
                    DGChip(
                        title: option.title, selected: selectedEquipment == option,
                        isEmpty: !facets.equipment.contains(option.rawValue)
                    ) {
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

    /// On iOS 27 a `.searchable` inside a plain `Tab` without an explicit placement shows no
    /// field at all (the system reserves search for a `role: .search` tab), which made the
    /// library unsearchable — so the drawer is pinned there. On iOS 26 the default drawer that
    /// collapses on scroll is kept: pinning it would cost ~52 pt of the list on the shipping OS
    /// for a problem it does not have, and would differ from `ExercisePickerSheet`'s field.
    private var searchPlacement: SearchFieldPlacement {
        if #available(iOS 27, *) {
            return .navigationBarDrawer(displayMode: .always)
        }
        return .navigationBarDrawer(displayMode: .automatic)
    }

    /// Re-reads the store: the catalogue, the placeholder's count (a `fetchCount`, not a
    /// materialised 1 500-row fetch) and the active profile. Then filters.
    private func reload() {
        catalogue = store.exerciseCatalogue()
        totalCount = store.fetchCount(Self.liveExerciseCount())
        profile = store.activeProfile()
        refresh()
    }

    /// Live rows only — the same `mergedIntoID == nil` rule as `WorkoutStore.isLive`, as a
    /// predicate so the count never materialises the library.
    private static func liveExerciseCount() -> FetchDescriptor<ExerciseModel> {
        FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.mergedIntoID == nil })
    }

    /// Filters the held catalogue in memory; no store round trip.
    private func refresh() {
        guard let catalogue else { return }
        let interval = signposter.beginInterval("LibraryView.refresh")
        defer { signposter.endInterval("LibraryView.refresh", interval) }
        let all = store.exercises(
            in: catalogue, matching: searchText, muscle: selectedMuscle,
            equipment: selectedEquipment?.rawValue, favoritesOnly: favoritesOnly, customOnly: customOnly,
            includeSecondary: includeSecondary
        )
        // The chips answer "what would still match": the profile applies unless "show all".
        facets = store.libraryFacets(
            in: catalogue, matching: searchText, favoritesOnly: favoritesOnly, customOnly: customOnly,
            availability: showAllEquipment ? nil : availability, selectedMuscle: selectedMuscle,
            selectedEquipment: selectedEquipment?.rawValue, includeSecondary: includeSecondary
        )
        guard let availability else {
            hidden = HiddenCounts()
            exercises = all
            return
        }
        exercises = ExercisePickerFilter.visible(
            all, availability: availability, showingAll: showAllEquipment, hidden: &hidden
        )
    }

    /// Nil (no filter) unless the active profile leaves some equipment or station out.
    private var availability: EquipmentAvailability? {
        guard let profile, profile.restrictsLibrary else { return nil }
        return profile.availability
    }

    /// The save bumps `changeToken`, and this tab is showing, so `reload()` follows on its own.
    private func toggleFavorite(_ id: UUID) {
        store.toggleFavorite(id: id)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        LibraryView()
            .environment(store)
            .environment(Preferences())
    }
}
