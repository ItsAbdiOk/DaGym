import Foundation

/// The three root tabs of the redesign, in bar order: Today, Train, You. Everything that used
/// to be a tab of its own (Progress, Library, Coach) is one tap deep from You. Drives the
/// system `TabView` in `RootView`.
enum DGTab: String, CaseIterable, Identifiable {
    case today, train, you

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .train: "Train"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .today: "house.fill"
        case .train: "dumbbell.fill"
        case .you: "person.fill"
        }
    }

    /// `DaGymUITests` taps tabs by these, so they must match `A11yID`.
    var accessibilityID: String {
        switch self {
        case .today: A11yID.tabToday
        case .train: A11yID.tabTrain
        case .you: A11yID.tabYou
        }
    }
}
