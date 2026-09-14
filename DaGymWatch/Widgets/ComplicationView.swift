import SwiftUI
import WidgetKit

/// The one view behind every family. Resting takes over each of them; otherwise the circular
/// rings the streak, the corner names the next session, the rectangular is the Smart Stack
/// card ("Push A today" / "Idle · 12-week streak").
struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchSnapshotEntry

    private var snapshot: WatchSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: Text(inlineText)
        default: rectangular
        }
    }

    // MARK: - Circular: streak ring, fills across the week

    @ViewBuilder private var circular: some View {
        if let rest = snapshot.rest {
            let start = rest.endDate.addingTimeInterval(-Double(rest.totalSeconds))
            ProgressView(timerInterval: start...rest.endDate, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Text(timerInterval: Date.now...rest.endDate, countsDown: true)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .progressViewStyle(.circular)
            .tint(.orange)
            .widgetAccentable()
            .accessibilityLabel(inlineText)
        } else {
            Gauge(value: Double(snapshot.trainedThisWeek.filter { $0 }.count), in: 0...7) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: -2) {
                    Text("\(snapshot.streakWeeks)").font(.system(size: 17, weight: .bold).monospacedDigit())
                    Text("wk").font(.system(size: 9, weight: .medium))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.orange)
            .widgetAccentable()
            .accessibilityLabel(inlineText)
        }
    }

    // MARK: - Corner: next session

    @ViewBuilder private var corner: some View {
        if let rest = snapshot.rest {
            Text(timerInterval: Date.now...rest.endDate, countsDown: true)
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .widgetCurvesContent()
                .widgetLabel { Text("Rest · \(rest.nextLabel)") }
                .widgetAccentable()
        } else {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 20, weight: .semibold))
                .widgetLabel { Text(cornerLabel) }
                .widgetAccentable()
        }
    }

    private var cornerLabel: String {
        guard let name = snapshot.nextRoutineName else { return "No session planned" }
        guard let date = snapshot.nextSessionDate else { return name }
        if snapshot.isNextToday { return "\(name) · \(date.formatted(.dateTime.hour().minute()))" }
        return "\(name) · \(date.formatted(.dateTime.weekday(.abbreviated)))"
    }

    // MARK: - Rectangular: Smart Stack card

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let rest = snapshot.rest {
                Text("DaGym · resting").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(timerInterval: Date.now...rest.endDate, countsDown: true)
                    .font(.system(size: 26, weight: .bold).monospacedDigit())
                    .foregroundStyle(.orange)
                Text("next \(rest.nextLabel)").font(.system(size: 12)).lineLimit(1)
            } else {
                Text("DaGym").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(headline).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text("Idle · \(snapshot.streakWeeks)-week streak")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    private var headline: String {
        guard let name = snapshot.nextRoutineName else { return "Nothing planned" }
        if snapshot.isNextToday { return "\(name) today" }
        guard let date = snapshot.nextSessionDate else { return name }
        return "\(name) \(date.formatted(.dateTime.weekday(.abbreviated)))"
    }

    private var inlineText: String {
        if let rest = snapshot.rest { return "Rest · next \(rest.nextLabel)" }
        return "\(snapshot.streakWeeks)-week streak · \(headline)"
    }
}
