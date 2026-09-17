import GymCore
import SwiftUI

/// One weekday row of the Schedule segment: "Mon", the routines planned that day (or "Rest"),
/// and an accent "Move" / "Add". The whole row is a menu — the day editor — that ticks
/// routines on and off the weekly plan (in tap order, the order they merge when the day
/// starts), clears the day to rest, or moves this week's session to another date. Today's row
/// carries a faint accent wash.
struct ScheduleDayRow: View {
    var date: Date
    var weekday: Weekday
    var isToday: Bool
    var isLast: Bool
    /// Every routine, for the menu's toggles.
    var routines: [RoutineInfo]
    /// What is actually on this date — the weekly plan plus any moved session.
    var planned: [RoutineInfo]
    /// The weekly plan for this weekday, which is what the toggles edit.
    var templateIDs: [UUID]
    var onToggle: (UUID) -> Void
    var onRest: () -> Void
    /// Nil for a date already gone this week — there's no session left to move.
    var onMove: (() -> Void)?

    var body: some View {
        Menu {
            if let onMove, !planned.isEmpty {
                Button("Move this session…", systemImage: "calendar", action: onMove)
            }
            Button("Rest day", systemImage: "moon.zzz", action: onRest)
            Section("Every \(weekday.displayName)") {
                ForEach(routines) { routine in
                    Toggle(routine.name, isOn: Binding(
                        get: { templateIDs.contains(routine.id) }, set: { _ in onToggle(routine.id) }
                    ))
                }
            }
        } label: {
            HStack(spacing: DGSpace.s3) {
                Text(weekday.shortLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
                    .frame(width: 34, alignment: .leading)
                Text(planned.isEmpty ? "Rest" : RoutineInfo.joinedNames(planned))
                    .font(.system(size: 15))
                    .foregroundStyle(planned.isEmpty ? DGColor.ink3 : DGColor.ink1)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(planned.isEmpty ? "Add" : "Move")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DGColor.coralText)
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 46)
            .background(isToday ? DGColor.coral.opacity(0.08) : .clear)
            .contentShape(Rectangle())
            .trainRowDivider(isLast: isLast)
        }
        .buttonStyle(.dgRow)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let what = planned.isEmpty ? "Rest" : RoutineInfo.joinedNames(planned)
        return "\(weekday.displayName)\(isToday ? ", today" : ""), \(what)"
    }
}

/// Sheet: pick a new date for a planned session.
struct MoveSessionSheet: View {
    var request: MoveRequest
    var calendar: Calendar
    var onMove: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newDate: Date

    init(request: MoveRequest, calendar: Calendar, onMove: @escaping (Date) -> Void) {
        self.request = request
        self.calendar = calendar
        self.onMove = onMove
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: request.sourceDate) ?? request.sourceDate
        _newDate = State(initialValue: tomorrow)
    }

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text("Move session")
                    .font(DGFont.title2)
                    .foregroundStyle(DGColor.ink1)
                Text("Move \(request.routineName) to a new date. The original day becomes a rest day.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DatePicker("New date", selection: $newDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(DGColor.coral)
                .labelsHidden()
            DGPrimaryButton(title: "Move", action: { onMove(newDate); dismiss() })
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.hidden)
    }
}
