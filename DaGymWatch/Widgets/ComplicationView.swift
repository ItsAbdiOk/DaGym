import SwiftUI
import WidgetKit

struct WatchSnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WatchSnapshot

    /// The provider's timeline, here (compiled into the app too) so it can be tested: now,
    /// then the idle card at the rest's end, or — idle — the snapshot as it should read
    /// tomorrow morning. See `WatchSnapshotProvider` for the reload policy's reasoning.
    static func timeline(
        for snapshot: WatchSnapshot, now: Date, calendar: Calendar = .current
    ) -> Timeline<WatchSnapshotEntry> {
        var entries = [WatchSnapshotEntry(date: now, snapshot: snapshot)]
        if let rest = snapshot.rest {
            var idle = snapshot
            idle.rest = nil
            entries.append(WatchSnapshotEntry(date: rest.endDate, snapshot: idle))
            return Timeline(entries: entries, policy: .after(rest.endDate))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            let morning = snapshot.expiring(at: tomorrow, calendar: calendar)
            if morning != snapshot { entries.append(WatchSnapshotEntry(date: tomorrow, snapshot: morning)) }
        }
        return Timeline(entries: entries, policy: .never)
    }
}

/// The one view behind every family. Resting takes over each of them; otherwise the circular
/// rings the streak, the corner names the next session, the rectangular is the Smart Stack
/// card ("Push A today" / "Idle · 12-week streak"). `family` is passed in rather than read from
/// the environment so the watch app's `-dgWatchScreen complications` harness can render every
/// family at its real size (the simulator cannot add a complication).
struct ComplicationView: View {
    var entry: WatchSnapshotEntry
    var family: WidgetFamily
    /// True in the Smart Stack (the card has room for its "DaGym" header line); false on a
    /// watch face, where the rectangular slot is ~53 pt tall and takes two lines only.
    var isSmartStack = false

    private var snapshot: WatchSnapshot { entry.snapshot }
    /// The rest's end, never before now: `Text(timerInterval:)` traps on a range that runs
    /// backwards, and the provider's guard against a stale rest is one process away.
    private func restEnd(_ rest: WatchSnapshot.Rest) -> Date { max(rest.endDate, Date.now) }
    /// The spec's coral, for the untinted faces; `widgetAccentable` hands it to a tinted one.
    private let coral = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x57 / 255)

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
            let end = restEnd(rest)
            let start = end.addingTimeInterval(-Double(max(rest.totalSeconds, 0)))
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Text(timerInterval: Date.now...end, countsDown: true)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .progressViewStyle(.circular)
            .tint(coral)
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
            .tint(coral)
            .widgetAccentable()
            .accessibilityLabel(inlineText)
        }
    }

    // MARK: - Corner: next session

    @ViewBuilder private var corner: some View {
        if let rest = snapshot.rest {
            // The corner's inner area is ~30 pt on the 40 mm: "1:32" must shrink rather than
            // truncate to "1:…".
            Text(timerInterval: Date.now...restEnd(rest), countsDown: true)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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
                if isSmartStack {
                    Text("DaGym · resting")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                // 26 pt on the 80 pt card; 22 on a face's ~47–56 pt rectangular slot.
                Text(timerInterval: Date.now...restEnd(rest), countsDown: true)
                    .font(.system(size: isSmartStack ? 26 : 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(coral)
                Text("next \(rest.nextLabel)").font(.system(size: 12)).lineLimit(1)
            } else {
                if isSmartStack {
                    Text("DaGym").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
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

    /// One short line: the inline slot on a face is ~140 pt.
    private var inlineText: String {
        if let rest = snapshot.rest { return "Rest · next \(rest.nextLabel)" }
        return "\(snapshot.nextRoutineName ?? "No session") · \(snapshot.streakWeeks) wk"
    }
}
