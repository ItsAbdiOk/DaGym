import GymCore
import SwiftData
import SwiftUI

/// Home / Today — the app's landing screen. Shows the scheduled routine,
/// weekly goal, streak and recovery snapshot, all computed from real workout history.
struct HomeView: View {
    var routine: RoutineInfo?
    /// "Next: Pull B · Thursday" for the rest-day card, from `WorkoutStore.nextSession()`.
    /// `nil` when nothing is scheduled within the lookahead window.
    var nextSessionText: String?
    var onStart: () -> Void
    var onFreestyle: () -> Void
    var onBackfill: () -> Void
    var onSeeRecovery: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var streakCurrent = 0
    @State private var streakLongest = 0
    @State private var thisWeekCount = 0
    @State private var recoveryMap: [Muscle: Double] = [:]
    @State private var showingSettings = false
    @State private var deloadSuggestion: DeloadSuggestionInfo?
    @State private var hasSchedule = true

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    if let routine {
                        ScheduledCard(
                            routine: routine, isScheduled: hasSchedule, onStart: onStart,
                            onFreestyle: onFreestyle, onBackfill: onBackfill
                        )
                    } else {
                        RestDayCard(
                            nextSessionText: nextSessionText, onFreestyle: onFreestyle, onBackfill: onBackfill
                        )
                    }
                    HStack(spacing: DGSpace.s4) {
                        WeeklyGoalCard(done: thisWeekCount, total: preferences.weeklyGoal)
                        StreakCard(current: streakCurrent, longest: streakLongest)
                    }
                    RecoveryCard(map: recoveryMap, onSeeRecovery: onSeeRecovery)
                    if let deloadSuggestion {
                        WhyCard(
                            title: "Why a deload?", message: deloadSuggestion.reason,
                            primary: "Plan a deload week", secondary: "Not now",
                            labelColor: DGColor.warning,
                            onPrimary: planDeload, onSecondary: snoozeDeload
                        )
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .task { refresh() }
        .onChange(of: store.changeToken) { refresh() }
        .onChange(of: preferences.weeklyGoal) { refresh() }
        .onChange(of: preferences.weekStartsMonday) { refresh() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    /// The scheduled routine itself comes from `RootView` (it owns "Start"); everything else
    /// is one `HomeSnapshot` pass so the numbers agree with the widget and the Progress tab.
    private func refresh() {
        let snapshot = HomeSnapshot.make(store: store, preferences: preferences)
        streakCurrent = snapshot.streakCurrent
        streakLongest = snapshot.streakLongest
        thisWeekCount = snapshot.thisWeekCount
        recoveryMap = snapshot.recoveryMap
        deloadSuggestion = snapshot.deloadSuggestion
        hasSchedule = snapshot.hasSchedule
    }

    private func planDeload() {
        store.planDeloadWeek()
        deloadSuggestion = nil
    }

    private func snoozeDeload() {
        preferences.deloadSnoozedUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        preferences.deloadDismissedFingerprint = deloadSuggestion?.fingerprint
        deloadSuggestion = nil
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text(Self.todayLabel).dgLabel()
                Text("Today")
                    .font(DGFont.title1)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer()
            DGIconButton(symbol: "gearshape", accessibilityLabel: "Settings") { showingSettings = true }
        }
    }

    private static var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: Date()).uppercased()
    }
}

/// Coral-outlined card for the day's scheduled routine.
private struct ScheduledCard: View {
    var routine: RoutineInfo
    var isScheduled = true
    var onStart: () -> Void
    var onFreestyle: () -> Void
    var onBackfill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text(scheduledLabel).dgLabel(DGColor.coralText)
                    Text(routine.name)
                        .font(DGFont.title2)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                    Text(
                        "\(routine.exercises.count) exercises · \(routine.setCount) sets"
                            + " · ~\(routine.estimatedMinutes) min"
                    )
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                BodyMapPair(intensity: routine.hitMap, height: 44)
            }
            HStack(spacing: DGSpace.s3) {
                DGPrimaryButton(title: "Start", symbol: "play.fill", action: onStart)
                    .accessibilityIdentifier(A11yID.homeStart)
                DGIconButton(
                    symbol: "plus", size: 52,
                    accessibilityLabel: "Start freestyle workout", action: onFreestyle
                )
                .accessibilityIdentifier(A11yID.homeFreestyle)
                DGIconButton(
                    symbol: "calendar", size: 52, accessibilityLabel: "Log a past workout", action: onBackfill
                )
            }
        }
        .padding(DGSpace.s5)
        .background(DGColor.coralWash, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.coral, lineWidth: 1)
        }
    }

    private var scheduledLabel: String {
        let base = isScheduled ? "Scheduled" : "Suggested"
        guard let weekLabel = routine.weekLabel, !weekLabel.isEmpty else { return base }
        return "\(base) · \(weekLabel)"
    }
}

/// Coral-outlined card shown when nothing is scheduled today.
private struct RestDayCard: View {
    var nextSessionText: String?
    var onFreestyle: () -> Void
    var onBackfill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text(HomeSnapshot.restDayHeadline).dgLabel(DGColor.coralText)
            Text(nextSessionText ?? "Nothing scheduled")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("No routine scheduled today. Start a freestyle workout whenever you're ready.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            HStack(spacing: DGSpace.s3) {
                DGPrimaryButton(title: "Start a Freestyle Workout", symbol: "plus", action: onFreestyle)
                    .accessibilityIdentifier(A11yID.homeStart)
                DGIconButton(
                    symbol: "calendar", size: 52, accessibilityLabel: "Log a past workout", action: onBackfill
                )
            }
        }
        .padding(DGSpace.s5)
        .background(DGColor.coralWash, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.coral, lineWidth: 1)
        }
    }
}

/// Half-width "3 / 4" weekly goal card with a segmented progress bar.
private struct WeeklyGoalCard: View {
    var done: Int
    var total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Weekly Goal").dgLabel()
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(done)")
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.ink1)
                Text("/ \(total)")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index < done ? DGColor.coral : DGColor.surface3)
                        .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DGSpace.s4)
        .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
    }
}

/// Half-width gold "streak" card.
private struct StreakCard: View {
    var current: Int
    var longest: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Streak").dgLabel()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(current)")
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.prGoldText)
                Text(current == 1 ? "week" : "weeks")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            Text("Longest: \(longest) \(longest == 1 ? "week" : "weeks")")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DGSpace.s4)
        .background(
            DGColor.prGold.opacity(0.10), in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.prGold.opacity(0.35), lineWidth: 1)
        }
    }
}

/// Recovery snapshot with a "see map" link.
private struct RecoveryCard: View {
    var map: [Muscle: Double]
    var onSeeRecovery: () -> Void

    private var headline: (title: String, body: String) { Recovery.headline(map: map) }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack {
                Text("Recovery").dgLabel()
                Spacer()
                Button("See Map", action: onSeeRecovery)
                    .buttonStyle(.plain)
                    .font(DGFont.condensedLabel(12))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.coralText)
            }
            HStack(alignment: .top, spacing: DGSpace.s4) {
                BodyMapPair(mode: .recovery, intensity: map, height: 56)
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text(headline.title)
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    Text(headline.body)
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dgCard()
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        HomeView(
            routine: SampleData.pushA,
            onStart: {}, onFreestyle: {}, onBackfill: {}, onSeeRecovery: {}
        )
        .environment(WorkoutStore(context: container.mainContext))
        .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}

#Preview("Rest day") {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        HomeView(
            routine: nil, nextSessionText: "Next: Pull B · Thursday",
            onStart: {}, onFreestyle: {}, onBackfill: {}, onSeeRecovery: {}
        )
        .environment(WorkoutStore(context: container.mainContext))
        .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
