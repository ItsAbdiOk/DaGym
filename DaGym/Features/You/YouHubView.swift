import GymCore
import SwiftUI

/// The "You" tab from the redesign: a week ring with volume / streak / bodyweight, the next
/// scheduled session, a six-tile "Go to" grid and three setup rows. Everything that used to be
/// a tab of its own (Progress, Library, Coach) is one push away from here.
struct YouHubView: View {
    /// Switches the shell to the Train tab (the dark "Up next" card's View button).
    var onShowTrain: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var path = NavigationPath()
    @State private var summary = YouSummary()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s3) {
                        header
                        YouWeekCard(summary: summary)
                        if let next = summary.upNext {
                            YouUpNextCard(next: next, onView: onShowTrain)
                        }
                        Text("Go to").dgLabel().padding(.top, DGSpace.s2).padding(.horizontal, DGSpace.s1)
                        goToGrid
                        setupRows
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 110)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: YouDestination.self) { destination in
                destination.screen
            }
        }
        .task { refresh() }
        .refreshOnStoreChange(refresh)
    }

    private func refresh() {
        summary = YouSummary.make(store: store, preferences: preferences)
    }

    private var header: some View {
        HStack {
            Text("You")
                .font(DGFont.title1)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "line.3.horizontal", accessibilityLabel: "Settings") {
                path.append(YouDestination.settings)
            }
            .accessibilityIdentifier(A11yID.youSettings)
        }
        .padding(.horizontal, DGSpace.s1)
    }

    private var goToGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
            ForEach(YouDestination.gridOrder, id: \.self) { destination in
                NavigationLink(value: destination) {
                    YouGridTile(title: destination.title, symbol: destination.symbol)
                }
                .buttonStyle(DGPressStyle())
                .accessibilityIdentifier(destination.accessibilityID)
            }
        }
    }

    private var setupRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(YouDestination.rowOrder.enumerated()), id: \.element) { offset, destination in
                NavigationLink(value: destination) {
                    YouRow(
                        title: destination.title,
                        value: destination == .equipment ? summary.equipmentProfileName : nil,
                        isLast: offset == YouDestination.rowOrder.count - 1
                    )
                }
                .buttonStyle(DGPressStyle())
                .accessibilityIdentifier(destination.accessibilityID)
            }
        }
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.95), lineWidth: 0.5)
        }
    }
}

/// Where the hub can push. `screen` builds the destination lazily so the hub itself stays cheap.
enum YouDestination: Hashable {
    case progress, history, muscles, body, coach, settings, library, equipment, gymCard, insights

    static let gridOrder: [YouDestination] = [.progress, .history, .muscles, .body, .coach, .settings]
    static let rowOrder: [YouDestination] = [.library, .equipment, .gymCard]

    var title: String {
        switch self {
        case .progress: "Progress"
        case .history: "History"
        case .muscles: "Muscles"
        case .body: "Body"
        case .coach: "Coach"
        case .settings: "Settings"
        case .library: "Exercise library"
        case .equipment: "Equipment profiles"
        case .gymCard: "Gym card"
        case .insights: "Insights"
        }
    }

    var symbol: String {
        switch self {
        case .progress: "chart.bar.fill"
        case .history: "calendar"
        case .muscles: "figure.stand"
        case .body: "heart.fill"
        case .coach: "bubble.left.fill"
        case .settings: "gearshape.fill"
        case .library: "books.vertical.fill"
        case .equipment: "shippingbox.fill"
        case .gymCard: "barcode"
        case .insights: "lightbulb.fill"
        }
    }

    var accessibilityID: String {
        switch self {
        case .progress: A11yID.youProgress
        case .history: A11yID.youHistory
        case .muscles: A11yID.youMuscles
        case .body: A11yID.youBody
        case .coach: A11yID.youCoach
        case .settings: A11yID.youSettings
        case .library: A11yID.youLibrary
        case .equipment: A11yID.youEquipment
        case .gymCard: A11yID.youGymCard
        case .insights: A11yID.youInsights
        }
    }

    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .progress: HistoryTabView()
        case .history: HistoryTabView()
        case .muscles: RecoveryMapView()
        case .body: BodyView()
        case .coach: CoachChatScreen()
        case .settings: SettingsView()
        case .library: LibraryView()
        case .equipment: EquipmentProfilesScreen()
        case .gymCard: GymCardSheet()
        case .insights: InsightsScreen()
        }
    }
}

private struct YouGridTile: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DGColor.coral)
                .frame(height: 22)
            Text(title)
                .font(DGFont.caption)
                .foregroundStyle(DGColor.ink1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, DGSpace.s2)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.95), lineWidth: 0.5)
        }
    }
}

private struct YouRow: View {
    let title: String
    var value: String?
    var isLast = false

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            Text(title)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            if let value {
                Text(value)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.ink4)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(DGColor.hairline).frame(height: 0.5).padding(.leading, 15)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Settings' equipment section as a pushed screen of its own (the You hub's "Equipment
/// profiles" row).
struct EquipmentProfilesScreen: View {
    var body: some View {
        SettingsPage(title: "Equipment profiles") { EquipmentSettingsSection() }
    }
}
