import GymCore
import SwiftUI

/// Screen 1. Page one is today (1A routine scheduled / 1B nothing scheduled); a vertical swipe
/// reaches Settings (screen 8). Start never scrolls away: it is pinned in the bottom inset with
/// the streak line under it in the last safe band.
struct HomeView: View {
    @Environment(WatchStore.self) private var store
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            todayPage.tag(0)
            SettingsView().tag(1)
        }
        .tabViewStyle(.verticalPage)
        .onAppear {
            store.refreshHome()
            if store.debugOpensSettings { page = 1 }
        }
    }

    @ViewBuilder private var todayPage: some View {
        if let routine = store.home.todaysRoutine {
            ScheduledHomeView(routine: routine)
        } else {
            RestDayHomeView()
        }
    }
}

/// 1A: one card holds the whole routine so the list reads as context, not a menu.
struct ScheduledHomeView: View {
    @Environment(WatchStore.self) private var store
    var routine: RoutineInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(routine.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
                Text("\(routine.exercises.count) exercises · \(routine.estimatedMinutes) min")
                    .font(WatchFont.body)
                    .foregroundStyle(WatchColor.inkSecondary)
                VStack(spacing: 0) {
                    ForEach(Array(store.home.todaysLines.enumerated()), id: \.offset) { index, line in
                        HStack {
                            Text(line.name).font(WatchFont.body).foregroundStyle(WatchColor.ink).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(line.sets).font(WatchFont.secondary).foregroundStyle(WatchColor.inkSecondary)
                        }
                        .frame(height: 30)
                        if index < store.home.todaysLines.count - 1 {
                            Divider().overlay(WatchColor.separator)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: WatchMetric.cardRadius).fill(WatchColor.card))
            }
            .padding(.horizontal, WatchMetric.gutter)
        }
        .safeAreaInset(edge: .bottom) { HomeFooter(primary: primaryTitle, action: startAction) }
    }

    private var primaryTitle: String { store.home.resumableWorkoutID == nil ? "Start" : "Resume" }

    private func startAction() {
        if let workoutID = store.home.resumableWorkoutID {
            store.resume(workoutID: workoutID)
        } else {
            store.start(routineID: routine.id)
        }
    }
}

/// 1B: 46 pt rows with the count right-aligned; Freestyle is the tinted capsule, not a row.
struct RestDayHomeView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                SafeBandText(text: "Rest day", font: WatchFont.title, color: WatchColor.ink)
                ForEach(store.home.routines) { routine in
                    ListRow(title: routine.name, trailing: "\(routine.exercises.count) ex") {
                        store.start(routineID: routine.id)
                    }
                }
                if store.home.routines.isEmpty {
                    Text("Routines sync from your iPhone.")
                        .font(WatchFont.body)
                        .foregroundStyle(WatchColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, WatchMetric.gutter)
        }
        .safeAreaInset(edge: .bottom) {
            HomeFooter(primary: store.home.resumableWorkoutID == nil ? "Freestyle" : "Resume") {
                if let workoutID = store.home.resumableWorkoutID {
                    store.resume(workoutID: workoutID)
                } else {
                    store.start(routineID: nil)
                }
            }
        }
    }
}

/// The pinned capsule plus the streak / next-day line in the last safe band.
private struct HomeFooter: View {
    @Environment(WatchStore.self) private var store
    var primary: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            CapsuleButton(title: primary, action: action)
                .padding(.horizontal, WatchMetric.gutter)
            SafeBandText(text: footerLine)
                .frame(height: WatchMetric.isSmall ? 18 : WatchMetric.safeBand)
        }
        .background(WatchColor.background.opacity(0.92))
    }

    private var footerLine: String {
        var parts: [String] = []
        if store.home.streakWeeks > 0 { parts.append("\(store.home.streakWeeks)-week streak") }
        if let next = store.home.nextLabel { parts.append(next) }
        return parts.isEmpty ? "No streak yet" : parts.joined(separator: " · ")
    }
}
