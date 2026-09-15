import SwiftUI
import WidgetKit

#if DEBUG
/// `-dgWatchScreen complications`: every complication family at its real size on black, in
/// both states (idle and resting), so the simulator — which cannot add a complication — can
/// still be screenshotted against the spec's screen 7 / 3D. Four vertical pages (`page`, from
/// `complications`, `complications-1` …): circular + corner, rectangular, Smart Stack card,
/// inline.
///
/// Sizes are the HIG's complication specifications per case, keyed on the screen width the
/// way `WatchMetric` is. `widgetLabel` / `widgetCurvesContent` only render inside WidgetKit,
/// so the corner's curved label is echoed as plain text under its glyph here.
struct WatchComplicationsDebugView: View {
    @State var page: Int

    private let idle: WatchSnapshot = {
        var snapshot = WatchSnapshot(streakWeeks: 12, nextRoutineName: "Push A", isNextToday: true)
        snapshot.trainedThisWeek = [true, true, false, true, false, false, false]
        snapshot.nextSessionDate = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: .now)
        return snapshot
    }()

    private var resting: WatchSnapshot {
        var snapshot = idle
        snapshot.rest = WatchSnapshot.Rest(
            endDate: Date.now.addingTimeInterval(92), totalSeconds: 150, nextLabel: "100 × 5",
            workoutTitle: "Push A"
        )
        return snapshot
    }

    var body: some View {
        TabView(selection: $page) {
            VStack(spacing: 10) {
                row("Circular", .accessoryCircular, size: Sizes.circular)
                row("Corner", .accessoryCorner, size: Sizes.corner)
            }
            .tag(0)
            row("Rectangular", .accessoryRectangular, size: Sizes.rectangular).tag(1)
            row("Smart Stack", .accessoryRectangular, size: Sizes.smartStack, glass: true).tag(2)
            row("Inline", .accessoryInline, size: Sizes.inline).tag(3)
        }
        .tabViewStyle(.verticalPage)
        .background(Color.black.ignoresSafeArea())
    }

    private func row(
        _ title: String, _ family: WidgetFamily, size: CGSize, glass: Bool = false
    ) -> some View {
        VStack(spacing: 4) {
            Text("\(title) \(Int(size.width))×\(Int(size.height))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            // The wide families stack; the round ones sit side by side.
            if size.width * 2 + 8 > Sizes.width {
                cell(idle, family: family, size: size, glass: glass)
                cell(resting, family: family, size: size, glass: glass)
            } else {
                HStack(spacing: 8) {
                    cell(idle, family: family, size: size, glass: glass)
                    cell(resting, family: family, size: size, glass: glass)
                }
            }
        }
    }

    private func cell(
        _ snapshot: WatchSnapshot, family: WidgetFamily, size: CGSize, glass: Bool
    ) -> some View {
        let entry = WatchSnapshotEntry(date: .now, snapshot: snapshot)
        return VStack(spacing: 2) {
            ComplicationView(entry: entry, family: family, isSmartStack: glass)
                .padding(.horizontal, glass ? 10 : 0)
                .frame(width: size.width, height: size.height)
                .background(
                    RoundedRectangle(cornerRadius: family == .accessoryCircular ? size.width / 2 : 12)
                        .fill(glass ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: family == .accessoryCircular ? size.width / 2 : 12))
            if family == .accessoryCorner {
                Text(snapshot.rest.map { "Rest · \($0.nextLabel)" } ?? "Push A · 18:30")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// HIG complication sizes in points, by case (40 mm / 41 mm / 44 mm / 45 mm / 49 mm).
    @MainActor
    private enum Sizes {
        static var width: CGFloat { WatchMetric.screenWidth }

        static var circular: CGSize { square(pick(42, 44.5, 47, 50, 54)) }

        static var corner: CGSize { square(pick(40, 42, 44, 46, 50)) }

        private static func square(_ side: CGFloat) -> CGSize { CGSize(width: side, height: side) }

        /// One value per case, smallest first (40, 41, 44, 45, 49 mm).
        private static func pick(_ values: CGFloat...) -> CGFloat {
            let index = width <= 162 ? 0 : width <= 176 ? 1 : width <= 184 ? 2 : width < 205 ? 3 : 4
            return values[min(index, values.count - 1)]
        }

        static var rectangular: CGSize {
            CGSize(width: pick(150, 160, 166, 178, 190), height: pick(47, 50, 53, 56, 61))
        }

        static var smartStack: CGSize {
            CGSize(width: width - 16, height: width <= 176 ? 72 : 80)
        }

        static var inline: CGSize { CGSize(width: width - 30, height: 20) }
    }
}
#endif
