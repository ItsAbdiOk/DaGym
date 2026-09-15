import SwiftUI

/// One day of `MonthCalendarSheet`: number, filled for trained, ringed for planned, arrow for
/// rescheduled.
struct MonthCalendarDayCell: View {
    var day: MonthCalendarDay
    var isSelected: Bool

    var body: some View {
        ZStack {
            if day.workoutID != nil {
                Circle().fill(DGColor.coral)
            } else if !day.plannedRoutineIDs.isEmpty {
                Circle().strokeBorder(DGColor.coral, lineWidth: 2)
            }
            if isSelected {
                Circle().strokeBorder(DGColor.ink1, lineWidth: 2).padding(-3)
            }
            Text("\(day.dayNumber)")
                .font(day.isToday ? DGFont.condensedLabel(15) : DGFont.subhead)
                .foregroundStyle(day.workoutID != nil ? DGColor.inkOnCoral : DGColor.ink1)
            if day.isRescheduled {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DGColor.coralText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(3)
            }
        }
        .frame(width: 40, height: 40)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
}

/// One legend entry under the month grid: swatch + label.
struct MonthCalendarLegendDot: View {
    enum Kind { case filled, ring, arrow }

    var kind: Kind
    var label: String

    var body: some View {
        HStack(spacing: DGSpace.s1) {
            switch kind {
            case .filled: Circle().fill(DGColor.coral).frame(width: 10, height: 10)
            case .ring: Circle().strokeBorder(DGColor.coral, lineWidth: 2).frame(width: 10, height: 10)
            case .arrow:
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DGColor.coralText)
            }
            Text(label).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
