import GymCore
import SwiftData
import SwiftUI

/// The month grid on the History page: trained days tinted by tonnage, planned days dashed,
/// today ringed. Tapping a day opens a panel under the grid — View workout for a trained day,
/// Move session when something is planned, Log a past workout when the day isn't in the future.
struct MonthCalendarCard: View {
    var records: [WorkoutRecord]
    var schedule: WeeklySchedule
    var routines: [RoutineInfo]
    var onOpenWorkout: (UUID) -> Void
    var onBackfill: (Date) -> Void
    /// (source date, new date, routine ids) — the caller saves the schedule.
    var onMove: (Date, Date, [UUID]) -> Void

    @Environment(Preferences.self) private var preferences
    @State private var month = Date()
    /// Rebuilt only when the month or the inputs change — as a computed property it regrouped
    /// every record and looked up 30 schedule days on every tap of a day cell.
    @State private var model: MonthCalendarModel?
    @State private var selected: MonthCalendarDay?
    @State private var moveDate: Date?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            monthHeader
            VStack(spacing: 8) {
                weekdayLabels
                grid
            }
            legend
            if let selected {
                dayPanel(selected)
            }
        }
        .dgCard(radius: 24, padding: 18)
        .dgAnimation(DGMotion.standard, value: selected)
        .onAppear(perform: rebuildModel)
        .onChange(of: month) { _, _ in rebuildModel() }
        .onChange(of: records) { _, _ in rebuildModel() }
        .onChange(of: schedule) { _, _ in rebuildModel() }
        .onChange(of: routines) { _, _ in rebuildModel() }
        .onChange(of: preferences.weekStartsMonday) { _, _ in rebuildModel() }
    }

    private var calendar: Calendar { preferences.trainingCalendar }

    private func rebuildModel() {
        model = MonthCalendarModel(
            month: month, records: records, schedule: schedule, routines: routines, calendar: calendar
        )
    }

    private var monthHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text(Self.monthLabel(month))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DGColor.ink1)
            Spacer()
            monthButton("chevron.left", label: "Previous month") { shift(by: -1) }
            monthButton("chevron.right", label: "Next month") { shift(by: 1) }
        }
    }

    private func monthButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DGColor.ink3)
                .frame(width: 30, height: 30)
                .background(DGColor.ink1.opacity(0.06), in: Circle())
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(label)
    }

    private var weekdayLabels: some View {
        LazyVGrid(columns: Self.columns, spacing: 0) {
            ForEach(Weekday.ordered(mondayFirst: preferences.weekStartsMonday), id: \.self) { weekday in
                Text(String(weekday.shortLabel.prefix(1)))
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(DGColor.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var grid: some View {
        let current = model ?? MonthCalendarModel(
            month: month, records: records, schedule: schedule, routines: routines, calendar: calendar
        )
        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(0..<current.leadingBlanks, id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
            ForEach(current.days) { day in
                Button {
                    select(day)
                } label: {
                    MonthCalendarDayCell(day: day, maxLoadKg: current.maxLoadKg, isSelected: day == selected)
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel(Self.accessibilityLabel(day))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 7) {
            Text("Lighter").font(.system(size: 11, weight: .semibold)).foregroundStyle(DGColor.ink3)
            ForEach(Array(MonthCalendarDayCell.ramp.dropFirst().enumerated()), id: \.offset) { _, tint in
                MonthCalendarLegendDot(kind: .filled(tint), label: "")
            }
            Text("Heavier").font(.system(size: 11, weight: .semibold)).foregroundStyle(DGColor.ink3)
            Spacer()
            MonthCalendarLegendDot(kind: .dashed, label: "Planned")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lighter to heavier tint by tonnage; dashed means planned")
    }

    @ViewBuilder
    private func dayPanel(_ day: MonthCalendarDay) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text(Self.dayLabel(day.date)).dgLabel()
            Text(day.title ?? "Nothing logged")
                .font(DGFont.title3)
                .foregroundStyle(day.title == nil ? DGColor.ink3 : DGColor.ink1)
            if let moveDate {
                movePicker(day, newDate: moveDate)
            } else {
                actions(day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func actions(_ day: MonthCalendarDay) -> some View {
        HStack(spacing: DGSpace.s2) {
            if let workoutID = day.workoutID {
                accentButton("View workout") { onOpenWorkout(workoutID) }
            } else {
                if !day.plannedRoutineIDs.isEmpty {
                    TrainQuietButton(title: "Move session") {
                        moveDate = calendar.date(byAdding: .day, value: 1, to: day.date) ?? day.date
                    }
                }
                if day.isPast || day.isToday {
                    accentButton("Log a past workout") { onBackfill(day.date) }
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
            HStack(spacing: DGSpace.s2) {
                TrainQuietButton(title: "Cancel") { moveDate = nil }
                accentButton("Move") {
                    onMove(day.date, newDate, day.plannedRoutineIDs)
                    moveDate = nil
                    selected = nil
                }
            }
        }
    }

    /// The prototype's filled accent button inside a card: 13.5/600 on the accent, radius 14.
    private func accentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DGColor.inkOnCoral)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(DGColor.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.dgControl)
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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static func monthLabel(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private static func dayLabel(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func accessibilityLabel(_ day: MonthCalendarDay) -> String {
        let base = dayLabel(day.date)
        switch day.state {
        case .trained(_, let title): return "\(base), trained, \(title)"
        case .planned(_, let title, let rescheduled):
            return "\(base), \(rescheduled ? "moved" : "planned"), \(title)"
        case .free: return base
        }
    }
}

#Preview {
    ZStack {
        AmbientWash()
        MonthCalendarCard(
            records: SampleData.history, schedule: WeeklySchedule(), routines: [SampleData.pushA],
            onOpenWorkout: { _ in }, onBackfill: { _ in }, onMove: { _, _, _ in }
        )
        .padding()
    }
    .environment(Preferences())
}
