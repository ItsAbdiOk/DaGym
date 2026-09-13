import GymCore
import SwiftData
import SwiftUI

/// Home / Today — the app's landing screen. Shows the scheduled routine,
/// weekly goal, streak, recovery snapshot and the coach's latest suggestion.
struct HomeView: View {
    var routine: RoutineInfo?
    var onStart: () -> Void
    var onFreestyle: () -> Void
    var onBackfill: () -> Void
    var onSeeRecovery: () -> Void

    @Environment(WorkoutStore.self) private var store
    @State private var workoutsThisWeek = 0

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
                        WeeklyGoalCard(done: workoutsThisWeek)
                        StreakCard()
                    }
                    RecoveryCard(onSeeRecovery: onSeeRecovery)
                    CoachRow()
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .task { refreshWeeklyCount() }
    }

    private func refreshWeeklyCount() {
        let calendar = Calendar.current
        let now = Date()
        workoutsThisWeek = store.history().filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear)
        }.count
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
                    Text("Scheduled · \(routine.weekLabel ?? "")".uppercased())
                        .dgLabel(DGColor.coralText)
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
                DGIconButton(symbol: "plus", size: 52, action: onFreestyle)
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
    private let total = 4

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
    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Streak").dgLabel()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("3")
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.prGoldText)
                Text("weeks")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            Text("Longest: 11 weeks")
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
    var onSeeRecovery: () -> Void

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
                BodyMapPair(mode: .recovery, intensity: SampleData.recoveryMap, height: 56)
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text("Chest still spent")
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    Text("Legs and back are fresh — today's push is fine, but Thursday should be a pull.")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dgCard()
    }
}

/// Violet coach suggestion row.
private struct CoachRow: View {
    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DGColor.aiVioletText)
                .frame(width: 36, height: 36)
                .background(DGColor.aiViolet.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach has 1 suggestion")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                Text("Swap cable fly for dips this week")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
        }
        .padding(DGSpace.s4)
        .background(
            DGColor.aiViolet.opacity(0.12),
            in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.aiViolet.opacity(0.3), lineWidth: 1)
        }
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
