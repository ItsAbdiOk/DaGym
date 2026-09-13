import Foundation

/// The five root tabs, in bar order. Drives the system `TabView` in `RootView`.
enum DGTab: String, CaseIterable, Identifiable {
    case today, routines, progress, library, coach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .routines: "Routines"
        case .progress: "Progress"
        case .library: "Library"
        case .coach: "Coach"
        }
    }

    var symbol: String {
        switch self {
        case .today: "house"
        case .routines: "dumbbell"
        case .progress: "chart.bar"
        case .library: "magnifyingglass"
        case .coach: "sparkles"
        }
    }

    /// `DaGymUITests` taps tabs by these, so they must match `A11yID`.
    var accessibilityID: String {
        switch self {
        case .today: A11yID.tabToday
        case .routines: A11yID.tabRoutines
        case .progress: A11yID.tabProgress
        case .library: A11yID.tabLibrary
        case .coach: A11yID.tabCoach
        }
    }
}
