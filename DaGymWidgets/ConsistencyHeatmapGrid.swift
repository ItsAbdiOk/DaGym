import GymCore
import SwiftUI

/// The 7-row × N-week grid `ConsistencyWidget` draws, sized to whatever space the family gives
/// it: 13 columns get ~12 pt squares on a medium widget, 26 columns ~8 pt on a large one. A
/// weekday initial sits beside every other row, in the snapshot's own week order. The parent
/// carries the accessibility label — at this size individual squares are not targets.
struct ConsistencyHeatmapGrid: View {
    var grid: [[DayCell?]]
    var calendar: Calendar

    @Environment(\.widgetPalette) private var palette

    private static let spacing: CGFloat = 3
    private static let maxSquare: CGFloat = 12
    private static let labelWidth: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let square = squareSize(in: proxy.size)
            HStack(alignment: .top, spacing: Self.spacing) {
                weekdayLabels(square: square)
                ForEach(Array(grid.indices), id: \.self) { column in
                    VStack(spacing: Self.spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            RoundedRectangle(cornerRadius: square * 0.2, style: .continuous)
                                .fill(color(for: grid[column][row]))
                                .frame(width: square, height: square)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    /// The largest square that fits both axes, capped so a 13-week grid on a wide widget does
    /// not balloon into tiles.
    private func squareSize(in size: CGSize) -> CGFloat {
        let columns = CGFloat(max(grid.count, 1))
        let byWidth = (size.width - Self.labelWidth - Self.spacing * columns) / columns
        let byHeight = (size.height - Self.spacing * 6) / 7
        return max(2, min(Self.maxSquare, byWidth, byHeight))
    }

    private func weekdayLabels(square: CGFloat) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { row, initial in
                Text(row.isMultiple(of: 2) ? initial : "")
                    .font(.system(size: min(9, square * 0.8), weight: .semibold))
                    .foregroundStyle(palette.inkMuted)
                    .frame(width: Self.labelWidth, height: square, alignment: .leading)
            }
        }
    }

    /// `veryShortStandaloneWeekdaySymbols` starts on Sunday whatever `firstWeekday` says; rotate
    /// it so row 0 is the snapshot's first day of the week.
    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + shift) % 7] }
    }

    private func color(for cell: DayCell?) -> Color {
        guard let cell else { return .clear }
        return palette.consistencyRamp[min(4, max(0, cell.level))]
    }
}
