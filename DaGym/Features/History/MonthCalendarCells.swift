import SwiftUI

/// One day of `MonthCalendarCard`: a rounded square tinted lighter → heavier by that day's
/// tonnage, a dashed outline for a planned day, and today as a dark ink square with an accent
/// ring. A rescheduled session keeps its small arrow.
struct MonthCalendarDayCell: View {
    var day: MonthCalendarDay
    /// The month's heaviest day; the tint ramp is relative to it.
    var maxLoadKg: Double
    var isSelected: Bool

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        ZStack {
            Self.shape.fill(fill)
            if day.isToday {
                Self.shape.strokeBorder(DGColor.coral.opacity(0.55), lineWidth: 2).padding(-3)
            } else if !day.plannedRoutineIDs.isEmpty {
                Self.shape.strokeBorder(
                    DGColor.ink1.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                )
            }
            if isSelected {
                Self.shape.strokeBorder(DGColor.ink1, lineWidth: 2)
            }
            Text("\(day.dayNumber)")
                .font(.system(size: 13, weight: day.isToday || level == 4 ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(ink)
            if day.isRescheduled {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DGColor.coralText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// 0 for a free day; 1…4 lighter → heavier as a share of the month's heaviest day.
    private var level: Int {
        Self.loadLevel(loadKg: day.loadKg, maxLoadKg: maxLoadKg)
    }

    static func loadLevel(loadKg: Double, maxLoadKg: Double) -> Int {
        guard loadKg > 0, maxLoadKg > 0 else { return 0 }
        let ratio = loadKg / maxLoadKg
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 0.75 { return 3 }
        return 4
    }

    /// The prototype's four accent mixes (28 / 55 / 80 / 100 %) over a low ink for a free day.
    static let ramp: [Color] = [
        DGColor.ink1.opacity(0.06), DGColor.coral.opacity(0.28), DGColor.coral.opacity(0.55),
        DGColor.coral.opacity(0.8), DGColor.coral
    ]

    // Today is the ink-on-page inversion: ink fill, page-coloured number. Both tokens flip
    // with the scheme, so in dark mode the cell is bone rather than a near-black square lost
    // against the card.
    var fill: Color {
        day.isToday ? DGColor.ink1 : Self.ramp[level]
    }

    var ink: Color {
        if day.isToday { return DGColor.bgBase }
        return level >= 3 ? DGColor.inkOnCoral : DGColor.ink1
    }
}

/// One legend entry under the month grid: swatch + label.
struct MonthCalendarLegendDot: View {
    enum Kind { case filled(Color), dashed, arrow }

    var kind: Kind
    var label: String

    var body: some View {
        HStack(spacing: 5) {
            switch kind {
            case .filled(let tint):
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint).frame(width: 15, height: 12)
            case .dashed:
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(DGColor.ink1.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .frame(width: 12, height: 12)
            case .arrow:
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DGColor.coralText)
            }
            if !label.isEmpty {
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(DGColor.ink3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHidden(label.isEmpty)
    }
}
