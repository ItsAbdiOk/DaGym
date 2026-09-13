import GymCore
import SwiftData
import SwiftUI

/// Home / Today — the app's landing screen. Shows the scheduled routine,
/// weekly goal, streak and recovery snapshot, all computed from real workout history.
struct HomeView: View {
    var routine: RoutineInfo?
    var onStart: () -> Void
    var onFreestyle: () -> Void
    var onBackfill: () -> Void
    var onSeeRecovery: () -> Void

    @Environment(WorkoutStore.self) private var store
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @State private var streakCurrent = 0
    @State private var streakLongest = 0
    @State private var thisWeekCount = 0
    @State private var recoveryMap: [Muscle: Double] = [:]

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    if let routine {
                        ScheduledCard(
                            routine: routine, onStart: onStart, onFreestyle: onFreestyle,
                            onBackfill: onBackfill
                        )
                    } else {
                        RestDayCard(onFreestyle: onFreestyle, onBackfill: onBackfill)
                    }
                    HStack(spacing: DGSpace.s4) {
                        WeeklyGoalCard(done: thisWeekCount, total: weeklyGoal)
                        StreakCard(current: streakCurrent, longest: streakLongest)
                    }
                    RecoveryCard(map: recoveryMap, onSeeRecovery: onSeeRecovery)
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .task { refresh() }
    }

    private func refresh() {
        let calendar = Calendar.current
        let now = Date()
        let streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: weeklyGoal, calendar: calendar, now: now
        )
        streakCurrent = streak.current
        streakLongest = streak.longest
        thisWeekCount = streak.thisWeekCount
        let since = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        recoveryMap = Recovery.map(events: store.recoveryEvents(since: since), now: now)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text(Self.todayLabel).dgLabel()
            Text("Today")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
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
                DGIconButton(symbol: "plus", size: 52, action: onFreestyle)
                    .accessibilityIdentifier(A11yID.homeFreestyle)
                DGIconButton(symbol: "calendar", size: 52, action: onBackfill)
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
        guard let weekLabel = routine.weekLabel, !weekLabel.isEmpty else { return "Scheduled" }
        return "Scheduled · \(weekLabel)"
    }
}

/// Coral-outlined card shown when nothing is scheduled today.
private struct RestDayCard: View {
    var onFreestyle: () -> Void
    var onBackfill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Rest Day").dgLabel(DGColor.coralText)
            Text("Next session: —")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("No routine scheduled. Start a freestyle workout whenever you're ready.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            HStack(spacing: DGSpace.s3) {
                DGPrimaryButton(title: "Start a Freestyle Workout", symbol: "plus", action: onFreestyle)
                    .accessibilityIdentifier(A11yID.homeStart)
                DGIconButton(symbol: "calendar", size: 52, action: onBackfill)
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
    } else {
        Text("Preview unavailable")
    }
}

#Preview("Rest day") {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        HomeView(
            routine: nil,
            onStart: {}, onFreestyle: {}, onBackfill: {}, onSeeRecovery: {}
        )
        .environment(WorkoutStore(context: container.mainContext))
    } else {
        Text("Preview unavailable")
    }
}
