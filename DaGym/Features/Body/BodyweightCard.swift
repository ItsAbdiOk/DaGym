import Charts
import SwiftUI
import UIKit

/// The Body hero card: "LATEST 82.4 kg" with the 30-day move and distance to goal on the
/// right, the last 12 weeks as a line with the goal dashed under it, then "Log a reading" and
/// "Edit goal" (and Sync, when Health bodyweight is on).
struct BodyweightCard: View {
    var series: [BodyMeasurementInfo]
    var isSyncing: Bool
    var onLog: () -> Void
    var onEditGoal: () -> Void
    var onSync: () -> Void

    @Environment(Preferences.self) private var preferences

    static let chartWeeks = 12

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            HStack(alignment: .top) {
                // The latest number is a door to logging the next one; the goal line to the goal.
                Button(action: onLog) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Latest").dgLabel()
                        latestValue
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dgRow)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Logs a reading")
                .accessibilityIdentifier(A11yID.bodyLatest)
                Spacer()
                Button(action: onEditGoal) {
                    VStack(alignment: .trailing, spacing: 7) {
                        if let move = thirtyDayMove {
                            Text(move)
                                .font(.system(size: 12.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(DGColor.coralText)
                        }
                        HStack(spacing: 3) {
                            Text(toGoal ?? "Set a goal")
                                .font(.system(size: 12.5))
                                .monospacedDigit()
                                .foregroundStyle(DGColor.ink3)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DGColor.ink4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dgRow)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Edits the goal")
                .accessibilityIdentifier(A11yID.bodyGoal)
            }
            if chartPoints.isEmpty {
                Text("Log your bodyweight to start the trend line.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .padding(.vertical, DGSpace.s3)
            } else {
                chart
                axisLabels
            }
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: DGRadius.lg, padding: 18)
    }

    private var latestValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let latest = series.last {
                Text(preferences.formatWeight(kg: latest.kg))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                Text(preferences.unitSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
            } else {
                Text("—").font(.system(size: 34, weight: .bold)).foregroundStyle(DGColor.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Numbers

    /// "−1.2 over 30 days": the latest reading against the first one inside the last 30 days.
    private var thirtyDayMove: String? {
        guard let latest = series.last,
              let since = Calendar.current.date(byAdding: .day, value: -30, to: latest.date),
              let baseline = series.first(where: { $0.date >= since }), baseline.id != latest.id else {
            return nil
        }
        let delta = preferences.weightUnit.display(kg: latest.kg - baseline.kg)
        return "\(Self.signed(delta)) over 30 days"
    }

    /// "2.1 kg to goal", or "At goal" within a tenth.
    private var toGoal: String? {
        guard let goalKg = preferences.bodyweightGoalKg, let latest = series.last else { return nil }
        let gap = abs(preferences.weightUnit.display(kg: latest.kg - goalKg))
        guard gap >= 0.05 else { return "At goal" }
        return "\(String(format: "%.1f", gap)) \(preferences.unitSymbol) to goal"
    }

    private static func signed(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + String(format: "%.1f", abs(value))
    }

    // MARK: - Chart

    private var chartPoints: [TrendChartView.Point] {
        let since = Calendar.current.date(byAdding: .weekOfYear, value: -Self.chartWeeks, to: Date())
            ?? .distantPast
        return series.filter { $0.date >= since }
            .map { TrendChartView.Point(date: $0.date, value: preferences.weightUnit.display(kg: $0.kg)) }
    }

    private var goal: Double? { preferences.bodyweightGoalKg.map { preferences.weightUnit.display(kg: $0) } }

    private var chart: some View {
        Chart {
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(DGColor.ink1.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(chartPoints) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                    .foregroundStyle(DGColor.coral)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .frame(height: 100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// The readings plus the goal, with a little air so the line never touches the card edge.
    private var yDomain: ClosedRange<Double> {
        var values = chartPoints.map(\.value)
        if let goal { values.append(goal) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(0.5, (high - low) * 0.15)
        return (low - pad)...(high + pad)
    }

    private var accessibilitySummary: String {
        var summary = ChartAccessibility.trendSummary(
            title: "Bodyweight", dates: chartPoints.map(\.date), values: chartPoints.map(\.value),
            format: ChartAccessibility.formatter(unit: preferences.unitSymbol)
        )
        if let goal {
            summary += ". Goal \(ChartAccessibility.formatter(unit: preferences.unitSymbol)(goal))"
        }
        return summary
    }

    private var axisLabels: some View {
        HStack {
            Text("\(Self.chartWeeks) weeks ago")
            Spacer()
            if let goal {
                Text("goal \(String(format: "%.1f", goal))").foregroundStyle(DGColor.ink4)
                Spacer()
            }
            Text("now")
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(DGColor.ink3)
        .accessibilityHidden(true)
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: DGSpace.s2) {
            Button(action: onLog) {
                Text("Log a reading")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(DGColor.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.dgControl)
            .accessibilityIdentifier(A11yID.bodyLogReading)
            TrainQuietButton(title: goalTitle, action: onEditGoal)
                .accessibilityIdentifier(A11yID.bodyEditGoal)
            if preferences.healthSyncBodyweight {
                TrainQuietButton(title: isSyncing ? "Syncing…" : "Sync", action: onSync)
                    .disabled(isSyncing)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var goalTitle: String { preferences.bodyweightGoalKg == nil ? "Set goal" : "Edit goal" }
}

/// "Progress photos" card — a dashed slot per pose holding the latest thumbnail, "Compare" on
/// the right, and a line saying whether the Face ID lock is on. Tapping anywhere opens the full
/// `ProgressPhotosView` (behind `PhotoLockGate`, see `BodyView.body`). Thumbnails are decoded
/// once into `thumbnails` so a Body re-render never touches JPEG bytes; the card re-fetches on
/// store saves only while it is on screen in the active scene.
struct ProgressPhotosCard: View {
    var onOpen: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var latest: [ProgressPhotoPose: ProgressPhotoInfo] = [:]
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var isOnScreen = false
    @State private var cardRefreshTask: Task<Void, Never>?

    /// A slot tapped: the photos screen opens on that pose, straight into the camera when the
    /// slot is empty.
    var onCapture: (ProgressPhotoPose) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Button(action: onOpen) {
                HStack(spacing: DGSpace.s1) {
                    ProgressCardTitle(title: "Progress photos", trailing: "Compare")
                    TrainChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.dgRow)
            .accessibilityHint("Opens progress photos")
            HStack(spacing: DGSpace.s2) {
                ForEach(ProgressPhotoPose.allCases) { pose in
                    Button { onCapture(pose) } label: { slot(pose) }
                        .buttonStyle(.dgControl)
                        .accessibilityHint(
                            latest[pose] == nil ? "Takes a \(pose.label) photo" : "Opens photos"
                        )
                }
            }
            Text(lockLine)
                .font(.system(size: 12))
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
        .task { await refresh() }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: store.changeToken) {
            guard isOnScreen, scenePhase == .active else { return }
            // One refresh in flight at a time: a delete then an add bump the token twice, and
            // the older fetch finishing last would put the older photos back.
            cardRefreshTask?.cancel()
            cardRefreshTask = Task { await refresh() }
        }
    }

    private var lockLine: String {
        preferences.lockPhotos
            ? "Face ID lock is on."
            : "Face ID lock is off. Turn it on in Settings \u{203A} Display."
    }

    /// A 3:4 slot: the pose's latest thumbnail, or a hatched dashed placeholder with the pose name.
    private func slot(_ pose: ProgressPhotoPose) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack(alignment: .bottom) {
            if let photo = latest[pose], let image = thumbnails[photo.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                HatchedFill()
                Text(pose.label.lowercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DGColor.ink2)
                    .padding(8)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay {
            if latest[pose] == nil {
                shape.strokeBorder(DGColor.ink1.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .accessibilityLabel(latest[pose] == nil ? "\(pose.label), no photo yet" : "\(pose.label) photo")
    }

    /// Re-fetches the latest photo per pose and decodes only thumbnails not already cached.
    private func refresh() async {
        var fetched: [ProgressPhotoPose: ProgressPhotoInfo] = [:]
        for pose in ProgressPhotoPose.allCases {
            fetched[pose] = store.latestPhoto(pose: pose)
        }
        let ids = Set(fetched.values.map(\.id))
        var decoded = thumbnails.filter { ids.contains($0.key) }
        for photo in fetched.values where decoded[photo.id] == nil {
            if let image = await PhotoDecoder.decodeForDisplay(photo.thumbnailData) {
                decoded[photo.id] = image
            }
        }
        guard !Task.isCancelled else { return }
        thumbnails = decoded
        latest = fetched
    }
}

/// The prototype's diagonal hatch for an empty photo slot.
private struct HatchedFill: View {
    var body: some View {
        Canvas { context, size in
            let stroke = DGColor.ink1.opacity(0.09)
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(stroke), lineWidth: 4)
                x += 9
            }
        }
    }
}
