import GymCore
import SwiftUI

/// Every screen a number, a name or a summary can be a door to. The You hub's tiles push
/// `YouDestination`; everything else that navigates — Today's tiles, a Records row, an
/// Insights card, the Progress hub's muscle tiles — pushes one of these instead, so a screen
/// is reachable the same way from whichever stack it is tapped in. Each root stack (Today,
/// Train, You, and the covers that wrap their own stack) registers it with
/// `screenDestinations()`; `screen` builds the destination lazily.
enum ScreenDestination: Hashable {
    case progress
    case thisWeek(ThisWeekSegment)
    case milestones
    case history
    case muscleMap(MuscleMapMode)
    /// The muscle map on Recovery with `muscle`'s detail sheet already open.
    case muscleDetail(Muscle)
    case body
    case insights
    case library
    /// Exercise detail for an exercise id; a stale id (deleted exercise) shows a short notice.
    case exercise(UUID)
    /// The By-exercise chart screen.
    case exerciseCharts
    case equipmentProfiles
    case healthSettings
    case settings
    case coach
    /// The routine builder on a saved routine — Today's hero card title, Train's cards.
    case routine(UUID)

    /// The pushed screen's inline title, which `TapTargetsTests` asserts on after a tap.
    var title: String {
        switch self {
        case .progress: "Progress"
        case .thisWeek: "This week"
        case .milestones: "Milestones"
        case .history: "History"
        case .muscleMap, .muscleDetail: "Muscle map"
        case .body: "Body"
        case .insights: "Insights"
        case .library: "Library"
        case .exercise: "Exercise"
        case .exerciseCharts: "By exercise"
        case .equipmentProfiles: "Equipment profiles"
        case .healthSettings: "Apple Health"
        case .settings: "Settings"
        case .coach: "Coach"
        case .routine: "Edit routine"
        }
    }

    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .progress: ProgressHubView()
        case .thisWeek(let segment): ThisWeekView(initialSegment: segment)
        case .milestones: MilestonesView()
        case .history: HistoryTabView()
        case .muscleMap(let mode): RecoveryMapView(initialMode: mode)
        case .muscleDetail(let muscle): RecoveryMapView(initialMode: .fatigue, initialMuscle: muscle)
        case .body: BodyView()
        case .insights: InsightsScreen()
        case .library: LibraryView()
        case .exercise(let id): ExerciseDetailScreen(exerciseID: id)
        case .exerciseCharts: ProgressScreen()
        case .equipmentProfiles: EquipmentProfilesScreen()
        case .healthSettings: HealthSettingsView(pushed: true)
        case .settings: SettingsView()
        case .coach: CoachChatScreen()
        case .routine(let id): RoutineBuilderScreen(routineID: id)
        }
    }
}

extension View {
    /// Registers `ScreenDestination` on a root stack, so any `NavigationLink(value:)` or
    /// `path.append` of one resolves wherever it was tapped.
    func screenDestinations() -> some View {
        navigationDestination(for: ScreenDestination.self) { destination in
            destination.screen
        }
    }
}

/// `ExerciseDetailView` by id — a Records row or an Insights card knows the exercise's id, not
/// its `ExerciseInfo`. Read once on push.
struct ExerciseDetailScreen: View {
    var exerciseID: UUID

    @Environment(WorkoutStore.self) private var store
    @State private var exercise: ExerciseInfo?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let exercise {
                ExerciseDetailView(exercise: exercise)
            } else if isMissing {
                EmptyState(
                    symbol: "dumbbell", title: "Exercise not found",
                    message: "It may have been deleted from the library."
                )
                .navigationTitle("Exercise")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                AmbientWash()
            }
        }
        .task {
            guard let model = store.fetchExerciseModel(id: exerciseID) else {
                isMissing = true
                return
            }
            exercise = store.exerciseInfo(for: model)
        }
    }
}

/// The routine builder pushed by a `ScreenDestination` rather than Train's own path: Cancel
/// and Save pop through `dismiss`, and the builder's own header stands in for the system bar.
struct RoutineBuilderScreen: View {
    var routineID: UUID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RoutineBuilderView(routineID: routineID, onDone: { dismiss() })
            .toolbar(.hidden, for: .navigationBar)
    }
}
