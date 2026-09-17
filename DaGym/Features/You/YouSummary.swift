import GymCore
import SwiftUI

/// The numbers on the You hub's week card and "Up next" strip — one store pass per refresh,
/// sharing `HomeSnapshot` so the ring, streak and bodyweight agree with Today and the widget.
struct YouSummary {
    struct UpNext: Hashable {
        var routineName: String
        var weekday: String
        var exerciseCount: Int
    }

    var thisWeekCount = 0
    var weeklyGoal = 4
    var volumeKg: Double = 0
    var volumeDeltaPercent: Double?
    var streakCurrent = 0
    var streakLongest = 0
    var bodyweightKg: Double?
    var bodyweightDeltaKg: Double?
    var upNext: UpNext?
    var equipmentProfileName: String?

    @MainActor
    static func make(store: WorkoutStore, preferences: Preferences, now: Date = Date()) -> YouSummary {
        let snapshot = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        let recap = store.weeklyRecap(
            for: now, weeklyGoal: preferences.weeklyGoal, calendar: preferences.trainingCalendar
        )
        var summary = YouSummary()
        summary.thisWeekCount = snapshot.thisWeekCount
        summary.weeklyGoal = preferences.weeklyGoal
        summary.volumeKg = recap.volumeKg
        summary.volumeDeltaPercent = recap.volumeDeltaPercent
        summary.streakCurrent = snapshot.streakCurrent
        summary.streakLongest = snapshot.streakLongest
        summary.bodyweightKg = snapshot.bodyweightKg
        summary.bodyweightDeltaKg = snapshot.bodyweightDeltaKg
        summary.equipmentProfileName = store.activeProfile()?.name
        let routines = store.routines()
        if let next = HomeSnapshot.nextSession(
            schedule: store.schedule(), routines: routines, calendar: preferences.trainingCalendar, now: now
        ) {
            summary.upNext = UpNext(
                routineName: next.routine.name,
                weekday: weekdayFormatter.string(from: next.date),
                exerciseCount: next.routine.exercises.count
            )
        }
        return summary
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

/// Week ring on the left, three stacked metrics on the right.
struct YouWeekCard: View {
    let summary: YouSummary
    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: DGSpace.s5) {
            ring
            VStack(alignment: .leading, spacing: 13) {
                metric(
                    "Volume",
                    value: preferences.formatVolume(kg: summary.volumeKg) + " " + preferences.unitSymbol,
                    trailing: summary.volumeDeltaPercent.map { Self.signed($0, suffix: "%") },
                    trailingTint: DGColor.coralText
                )
                metric(
                    "Streak", value: "\(summary.streakCurrent) w",
                    trailing: "best \(summary.streakLongest)", trailingTint: DGColor.ink3
                )
                metric(
                    "Bodyweight",
                    value: summary.bodyweightKg.map { preferences.formatWeight(kg: $0) } ?? "—",
                    trailing: summary.bodyweightDeltaKg.map {
                        Self.signed(preferences.weightUnit.display(kg: $0), suffix: "", decimals: 1)
                    },
                    trailingTint: DGColor.coralText
                )
            }
            Spacer(minLength: 0)
        }
        .dgCard(radius: DGRadius.xl)
    }

    private var ring: some View {
        let fraction = summary.weeklyGoal > 0
            ? min(1, Double(summary.thisWeekCount) / Double(summary.weeklyGoal)) : 0
        return ZStack {
            Circle().stroke(DGColor.ink1.opacity(0.1), lineWidth: 11)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(DGColor.coral, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(summary.thisWeekCount)")
                    .font(.system(size: 27, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                Text("of \(summary.weeklyGoal)")
                    .font(DGFont.caption)
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .frame(width: 104, height: 104)
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.thisWeekCount) of \(summary.weeklyGoal) sessions this week")
    }

    private func metric(_ label: String, value: String, trailing: String?, trailingTint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).dgLabel()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                if let trailing {
                    Text(trailing)
                        .font(DGFont.caption)
                        .foregroundStyle(trailingTint)
                }
            }
        }
    }

    private static func signed(_ value: Double, suffix: String, decimals: Int = 0) -> String {
        let magnitude = String(format: "%.\(decimals)f", abs(value))
        return (value < 0 ? "−" : "+") + magnitude + suffix
    }
}

/// The dark "Up next · Friday" strip with a white View pill.
struct YouUpNextCard: View {
    let next: YouSummary.UpNext
    var onView: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Up next · \(next.weekday)")
                    .dgLabel(.white.opacity(0.75))
                Text("\(next.routineName) · \(next.exerciseCount) exercises")
                    .font(DGFont.title3)
                    .foregroundStyle(.white)
            }
            Spacer()
            Button("View", action: onView)
                .font(DGFont.caption)
                .foregroundStyle(Color(hex: 0x1C1917))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white, in: Capsule())
                .buttonStyle(DGPressStyle())
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .background(
            Color(hex: 0x1C1917).opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

/// The floating accent "play" button that starts today's workout from Today and Train.
struct StartFAB: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DGColor.inkOnCoral)
                .frame(width: 62, height: 62)
                .background(DGColor.coral, in: Circle())
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(color: DGColor.coral.opacity(0.42), radius: 15, y: 12)
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel("Start workout")
        .accessibilityIdentifier(A11yID.homeStartFab)
    }
}
