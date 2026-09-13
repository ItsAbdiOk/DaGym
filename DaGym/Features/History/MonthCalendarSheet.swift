import GymCore
import SwiftData
import SwiftUI

/// One cell of the month grid: what happened (or is planned) on that day.
struct MonthCalendarDay: Identifiable, Hashable {
    enum State: Hashable {
        /// A finished workout exists; `workoutID` opens its detail.
        case trained(workoutID: UUID, title: String)
        /// Routines are scheduled; `rescheduled` when the date carries an override.
        case planned(routineIDs: [UUID], title: String, rescheduled: Bool)
        case free
    }

    var id: String { key }
    let key: String
    let date: Date
    let dayNumber: Int
    let state: State
    let isToday: Bool
    let isPast: Bool

    var workoutID: UUID? {
        if case .trained(let id, _) = state { return id }
        return nil
    }

    var plannedRoutineIDs: [UUID] {
        if case .planned(let ids, _, _) = state { return ids }
        return []
    }

    var isRescheduled: Bool {
        if case .planned(_, _, let rescheduled) = state { return rescheduled }
        return false
    }

    var title: String? {
        switch state {
        case .trained(_, let title), .planned(_, let title, _): title
        case .free: nil
        }
    }
}

/// Pure layout of a month for the calendar sheet: leading blanks so day 1 lands on its
/// weekday, then one `MonthCalendarDay` per day. A finished workout on a date wins over a
/// planned one, so a day never shows as both.
struct MonthCalendarModel: Hashable {
    let monthStart: Date
    let leadingBlanks: Int
    let days: [MonthCalendarDay]

    init(
        month: Date, records: [WorkoutRecord], schedule: WeeklySchedule, routines: [RoutineInfo],
        calendar: Calendar, now: Date = Date()
    ) {
        let components = calendar.dateComponents([.year, .month], from: month)
        let start = calendar.date(from: components) ?? month
        monthStart = start
        let weekday = calendar.component(.weekday, from: start)
        leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let today = calendar.startOfDay(for: now)
        let trained = Dictionary(grouping: records) { DateKey.string(for: $0.date, calendar: calendar) }
        days = (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = DateKey.string(for: date, calendar: calendar)
            let state: MonthCalendarDay.State
            if let record = trained[key]?.min(by: { $0.date < $1.date }) {
                state = .trained(workoutID: record.id, title: record.title)
            } else {
                let ids = schedule.routineIDs(on: date, calendar: calendar)
                let planned = ids.compactMap { id in routines.first { $0.id == id } }
                if planned.isEmpty {
                    state = .free
                } else {
                    state = .planned(
                        routineIDs: planned.map(\.id), title: RoutineInfo.joinedNames(planned),
                        rescheduled: schedule.isRescheduled(date, calendar: calendar)
                    )
                }
            }
            return MonthCalendarDay(
                key: key, date: date, dayNumber: offset + 1, state: state,
                isToday: calendar.isDate(date, inSameDayAs: today), isPast: date < today
            )
        }
    }

    var trainedCount: Int { days.filter { $0.workoutID != nil }.count }
    var plannedCount: Int { days.filter { !$0.plannedRoutineIDs.isEmpty }.count }
}

/// Month grid from History: trained days filled, planned days ringed, rescheduled ones marked
/// with an arrow. Tapping a trained day opens its detail; any other day offers Move Session
/// (when something is planned) or Log a Past Workout (when the day isn't in the future).
struct MonthCalendarSheet: View {
    var records: [WorkoutRecord]
    var schedule: WeeklySchedule
    var routines: [RoutineInfo]
    var onOpenWorkout: (UUID) -> Void
    var onBackfill: (Date) -> Void
    /// (source date, new date, routine ids) — the caller saves the schedule.
    var onMove: (Date, Date, [UUID]) -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    @State private var selected: MonthCalendarDay?
    @State private var moveDate: Date?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: DGSpace.s1), count: 7)

    var body: some View {
        VStack(spacing: DGSpace.s4) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            monthHeader
            weekdayLabels
            grid
            legend
            if let selected {
                dayPanel(selected)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .animation(DGMotion.standard, value: selected)
    }

    private var calendar: Calendar { preferences.trainingCalendar }

    private var model: MonthCalendarModel {
        MonthCalendarModel(
            month: month, records: records, schedule: schedule, routines: routines, calendar: calendar
        )
    }

    private var monthHeader: some View {
        HStack {
            DGIconButton(symbol: "chevron.left", size: 36, accessibilityLabel: "Previous month") {
                shift(by: -1)
            }
            Spacer()
            Text(Self.monthLabel(month))
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "chevron.right", size: 36, accessibilityLabel: "Next month") {
                shift(by: 1)
            }
        }
    }

    private var weekdayLabels: some View {
        LazyVGrid(columns: Self.columns, spacing: 0) {
            ForEach(Weekday.ordered(mondayFirst: preferences.weekStartsMonday), id: \.self) { weekday in
                Text(weekday.shortLabel).dgLabel().frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let current = model
        return LazyVGrid(columns: Self.columns, spacing: DGSpace.s1) {
            ForEach(0..<current.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 44)
            }
            ForEach(current.days) { day in
                Button {
                    select(day)
                } label: {
                    DayCell(day: day, isSelected: day == selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.accessibilityLabel(day))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: DGSpace.s4) {
            LegendDot(kind: .filled, label: "Trained")
            LegendDot(kind: .ring, label: "Planned")
            LegendDot(kind: .arrow, label: "Moved")
            Spacer()
        }
        .padding(.top, DGSpace.s1)
    }

    @ViewBuilder
    private func dayPanel(_ day: MonthCalendarDay) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text(Self.dayLabel(day.date)).dgLabel()
            Text(day.title ?? "Nothing logged")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(day.title == nil ? DGColor.ink3 : DGColor.ink1)
            if let moveDate {
                movePicker(day, newDate: moveDate)
            } else {
                actions(day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }

    @ViewBuilder
    private func actions(_ day: MonthCalendarDay) -> some View {
        HStack(spacing: DGSpace.s3) {
            if let workoutID = day.workoutID {
                DGPrimaryButton(title: "View Workout") {
                    dismiss()
                    onOpenWorkout(workoutID)
                }
            } else {
                if !day.plannedRoutineIDs.isEmpty {
                    glassButton("Move Session") {
                        moveDate = calendar.date(byAdding: .day, value: 1, to: day.date) ?? day.date
                    }
                }
                if day.isPast || day.isToday {
                    DGPrimaryButton(title: "Log a Past Workout") {
                        dismiss()
                        onBackfill(day.date)
                    }
                }
            }
        }
    }

    private func movePicker(_ day: MonthCalendarDay, newDate: Date) -> some View {
        VStack(spacing: DGSpace.s3) {
            DatePicker(
                "New date",
                selection: Binding(get: { newDate }, set: { moveDate = $0 }),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .tint(DGColor.coral)
            .font(DGFont.body)
            .foregroundStyle(DGColor.ink1)
            HStack(spacing: DGSpace.s3) {
                glassButton("Cancel") { moveDate = nil }
                DGPrimaryButton(title: "Move") {
                    onMove(day.date, newDate, day.plannedRoutineIDs)
                    moveDate = nil
                    selected = nil
                }
            }
        }
    }

    private func glassButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DGFont.condensedLabel(15))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .dgGlass(.regular, radius: DGRadius.lg)
        }
        .buttonStyle(DGPressStyle())
    }

    private func select(_ day: MonthCalendarDay) {
        moveDate = nil
        selected = day == selected ? nil : day
    }

    private func shift(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = next
        selected = nil
        moveDate = nil
    }

    private static func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date).uppercased()
    }

    private static func accessibilityLabel(_ day: MonthCalendarDay) -> String {
        let base = dayLabel(day.date).capitalized
        switch day.state {
        case .trained(_, let title): return "\(base), trained, \(title)"
        case .planned(_, let title, let rescheduled):
            return "\(base), \(rescheduled ? "moved" : "planned"), \(title)"
        case .free: return base
        }
    }
}

/// One day: number, filled for trained, ringed for planned, arrow for rescheduled.
private struct DayCell: View {
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

private struct LegendDot: View {
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
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            MonthCalendarSheet(
                records: SampleData.history, schedule: WeeklySchedule(), routines: [SampleData.pushA],
                onOpenWorkout: { _ in }, onBackfill: { _ in }, onMove: { _, _, _ in }
            )
            .environment(Preferences())
        }
}
