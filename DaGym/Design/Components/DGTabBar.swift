import SwiftUI

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
}

/// Floating glass-thick pill tab bar. Hidden during an active workout.
struct DGTabBar: View {
    @Binding var selected: DGTab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DGTab.allCases) { tab in
                let on = tab == selected
                Button {
                    guard !on else { return }
                    Haptics.step()
                    withAnimation(DGMotion.standard) { selected = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 22, weight: .semibold))
                        Text(tab.title)
                            .font(DGFont.tabLabel)
                            .tracking(1)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(on ? activeInk : idleInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if on {
                            Capsule().fill(pillFill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tabIdentifier(tab))
            }
        }
        .padding(6)
        .frame(height: 64)
        .dgGlass(.thick, in: Capsule())
        .shadow(color: .black.opacity(scheme == .dark ? 0.8 : 0.34), radius: 20, y: 16)
        .padding(.horizontal, 10)
    }

    private func tabIdentifier(_ tab: DGTab) -> String {
        switch tab {
        case .today: A11yID.tabToday
        case .routines: A11yID.tabRoutines
        case .progress: A11yID.tabProgress
        case .library: A11yID.tabLibrary
        case .coach: A11yID.tabCoach
        }
    }

    private var activeInk: Color { scheme == .dark ? DGColor.coral : Color(hex: 0xB83E2A) }
    private var idleInk: Color { DGColor.ink3 }
    private var pillFill: Color {
        scheme == .dark ? .white.opacity(0.14) : DGColor.coralPress.opacity(0.12)
    }
}

#Preview {
    @Previewable @State var tab = DGTab.today
    ZStack(alignment: .bottom) {
        AmbientWash()
        DGTabBar(selected: $tab)
    }
}
