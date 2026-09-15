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

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        if let profile, profile.restrictsLibrary {
                            EquipmentFilterBanner(
                                profileName: profile.name, hidden: hidden, showingAll: $showAllEquipment
                            )
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
            equipment: selectedEquipment?.rawValue, favoritesOnly: favoritesOnly, customOnly: customOnly
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

/// "Showing what's in Home · 212 hidden by equipment, 14 by machine · Show all" — the
/// equipment-profile filter's banner, shared by the library and the exercise picker. Tapping the
/// trailing word flips the filter.
struct EquipmentFilterBanner: View {
    var profileName: String
    var hidden = HiddenCounts()
    @Binding var showingAll: Bool

    /// "Showing what's in Home" plus how many rows the profile hides, split by the reason.
    static func title(profileName: String, hidden: HiddenCounts, showingAll: Bool) -> String {
        if showingAll { return "Showing all equipment" }
        var parts: [String] = []
        if hidden.byType > 0 { parts.append("\(hidden.byType) by equipment") }
        if hidden.byMachine > 0 { parts.append("\(hidden.byMachine) by machine") }
        guard !parts.isEmpty else { return "Showing what's in \(profileName)" }
        return "Showing what's in \(profileName) · hiding \(parts.joined(separator: ", "))"
    }

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
                .accessibilityHidden(true)
            Text(Self.title(profileName: profileName, hidden: hidden, showingAll: showingAll))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink2)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
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
