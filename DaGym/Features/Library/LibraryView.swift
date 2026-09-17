import GymCore
import SwiftData
import SwiftUI
import os

private let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

/// Exercise Library — search, filter chips and a white row group of exercises under the active
/// filter, driven by the store. Pushed from Train and You, so it has no stack of its own.
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

    /// The row group's scroll anchor for a body-map tap.
    private static let resultsAnchor = "library.results"

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s3) {
                        filterChipRow
                        refineChipRow
                        if showingMuscleMap {
                            LibraryMuscleMapCard(
                                counts: facets.muscleCounts, selected: selectedMuscle,
                                includeSecondary: $includeSecondary
                            ) { muscle in select(muscle, scrolling: proxy) }
                        }
                        if let profile, profile.restrictsLibrary {
                            EquipmentFilterBanner(
                                profileName: profile.name, hidden: hidden, showingAll: $showAllEquipment
                            )
                            .padding(.top, DGSpace.s1)
                        }
                        rows.id(Self.resultsAnchor)
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 110)
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

    /// "All" is the absence of every chip on its row: no muscle, not favourites, not mine.
    private var showingAll: Bool {
        selectedMuscle == nil && !favoritesOnly && !customOnly
    }

    /// The prototype's chip row — All · Favourites · every muscle · Mine. A chip that would
    /// find nothing under every *other* filter is dimmed and disabled; the selected one stays
    /// live so one tap clears it (`facets` is refreshed with the rows).
    private var filterChipRow: some View {
        chipStrip {
            DGChip(title: "All", selected: showingAll) {
                selectedMuscle = nil
                favoritesOnly = false
                customOnly = false
            }
            DGChip(title: "Favourites", selected: favoritesOnly) { favoritesOnly.toggle() }
            ForEach(Muscle.allCases) { muscle in
                DGChip(
                    title: muscle.displayName, selected: selectedMuscle == muscle,
                    isEmpty: !facets.muscles.contains(muscle)
                ) {
                    selectedMuscle = selectedMuscle == muscle ? nil : muscle
                }
            }
            DGChip(title: "Mine", selected: customOnly) { customOnly.toggle() }
        }
    }

    /// The second row narrows further: the body-map card's toggle, then equipment.
    private var refineChipRow: some View {
        chipStrip {
            byMuscleChip
            ForEach(EquipmentOption.allCases) { option in
                DGChip(
                    title: option.title, selected: selectedEquipment == option,
                    isEmpty: !facets.equipment.contains(option.rawValue)
                ) {
                    selectedEquipment = selectedEquipment == option ? nil : option
                }
            }
        }
    }

    /// A horizontal chip strip that scrolls edge to edge under the page gutter.
    private func chipStrip(@ViewBuilder _ chips: () -> some View) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7, content: chips)
                .padding(.horizontal, DGSpace.s4)
        }
        .padding(.horizontal, -DGSpace.s4)
    }

    /// Opens the body-map card; a chip like its neighbours so it reads as a filter control.
    private var byMuscleChip: some View {
        Button {
            withAnimation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion)) {
                showingMuscleMap.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Body map")
                Image(systemName: showingMuscleMap ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(DGFont.condensedLabel(12))
            .foregroundStyle(showingMuscleMap ? DGColor.inkOnCoral : DGColor.ink2)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background {
                if showingMuscleMap {
                    Capsule().fill(DGColor.coral)
                } else {
                    Capsule().fill(DGColor.surface2)
                        .overlay(Capsule().strokeBorder(DGColor.hairline, lineWidth: 0.5))
                }
            }
        }
        .buttonStyle(.dgControl)
        .accessibilityIdentifier(A11yID.libraryByMuscle)
        .accessibilityLabel("Explore by muscle")
        .accessibilityAddTraits(showingMuscleMap ? .isSelected : [])
        .accessibilityHint(showingMuscleMap ? "Hides the body map" : "Shows a body map to pick a muscle from")
    }

    /// The white row group. The rows stay lazy; the card is drawn behind the whole stack so
    /// hairlines and corners read as one list, as in the prototype.
    @ViewBuilder
    private var rows: some View {
        if exercises.isEmpty {
            EmptyState(
                symbol: "magnifyingglass", title: "No exercises",
                message: "Nothing matches these filters. Try another chip or clear the search."
            )
            .frame(maxWidth: .infinity)
            .padding(.top, DGSpace.s6)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { offset, exercise in
                    NavigationLink(value: exercise) {
                        LibraryRow(exercise: exercise, isLast: offset == exercises.count - 1)
                    }
                    .buttonStyle(DGPressStyle())
                    .contextMenu {
                        Button(
                            exercise.isFavorite ? "Remove from favourites" : "Add to favourites",
                            systemImage: exercise.isFavorite ? "star.slash" : "star"
                        ) { toggleFavorite(exercise.id) }
                    }
                }
            }
            .dgCard(radius: 14, padding: 0)
            .navigationDestination(for: ExerciseInfo.self) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
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

    /// The save bumps `changeToken`, and this screen is showing, so `reload()` follows on its own.
    private func toggleFavorite(_ id: UUID) {
        store.toggleFavorite(id: id)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            LibraryView()
        }
        .environment(store)
        .environment(Preferences())
    }
}
