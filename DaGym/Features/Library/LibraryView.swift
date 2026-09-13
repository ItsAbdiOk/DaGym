import GymCore
import SwiftUI

/// Exercise Library — search, filter chips and a scrolling list of
/// exercises grouped under the active filter.
struct LibraryView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case chest, barbell, favourites, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chest: "Chest"
            case .barbell: "Barbell"
            case .favourites: "Favourites"
            case .custom: "Custom"
            }
        }
    }

    @State private var exercises = SampleData.library
    @State private var searchText = ""
    @State private var selectedFilter: Filter? = .chest
    @State private var showingNewExercise = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        header
                        searchField
                        chipRow
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
                NewExerciseSheet { new in exercises.append(new) }
            }
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
            TextField("Search 480 exercises", text: $searchText)
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
                ForEach(Filter.allCases) { filter in
                    DGChip(title: filter.title, selected: selectedFilter == filter) {
                        selectedFilter = selectedFilter == filter ? nil : filter
                    }
                }
            }
        }
    }

    private var sectionLabel: some View {
        Text("\(sectionTitle) · \(filtered.count) exercises").dgLabel()
    }

    private var sectionTitle: String {
        selectedFilter?.title.uppercased() ?? "All"
    }

    private var rows: some View {
        LazyVStack(spacing: DGSpace.s3) {
            ForEach(filtered) { exercise in
                NavigationLink(value: exercise) {
                    LibraryRow(exercise: exercise)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: ExerciseInfo.self) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
    }

    private var filtered: [ExerciseInfo] {
        exercises.filter { matchesFilter($0) && matchesSearch($0) }
    }

    private func matchesFilter(_ exercise: ExerciseInfo) -> Bool {
        switch selectedFilter {
        case .chest: exercise.primary.contains(.chest)
        case .barbell: exercise.equipment == "Barbell"
        case .favourites: exercise.isFavorite
        case .custom: exercise.isCustom
        case nil: true
        }
    }

    private func matchesSearch(_ exercise: ExerciseInfo) -> Bool {
        searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
    }
}

/// One 72 pt row in the library list.
private struct LibraryRow: View {
    var exercise: ExerciseInfo

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
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.prGoldText)
                .frame(width: 28, height: 28)
                .background(DGColor.prGold.opacity(0.18), in: Circle())
        } else if exercise.loggingStyle == .weightedBodyweight {
            DGTag(text: "BW+", tint: DGColor.infoText, wash: DGColor.info.opacity(0.16))
        } else if exercise.isCustom {
            DGTag(text: "Mine", tint: DGColor.coralText, wash: DGColor.coralWash)
        }
    }
}

#Preview {
    LibraryView()
}
