import GymCore
import SwiftData
import SwiftUI

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
    /// Rebuilt only when the month or the inputs change — as a computed property it regrouped
    /// every record and looked up 30 schedule days on every tap of a day cell.
    @State private var model: MonthCalendarModel?
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

    @ViewBuilder
    private var grid: some View {
        let current = model ?? MonthCalendarModel(
            month: month, records: records, schedule: schedule, routines: routines, calendar: calendar
        )
        LazyVGrid(columns: Self.columns, spacing: DGSpace.s1) {
            ForEach(0..<current.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 44)
            }
            ForEach(current.days) { day in
                Button {
                    select(day)
                } label: {
                    MonthCalendarDayCell(day: day, isSelected: day == selected)
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel(Self.accessibilityLabel(day))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: DGSpace.s4) {
            MonthCalendarLegendDot(kind: .filled, label: "Trained")
            MonthCalendarLegendDot(kind: .ring, label: "Planned")
            MonthCalendarLegendDot(kind: .arrow, label: "Moved")
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
                .frame(minHeight: 52)
                .dgGlass(.regular, radius: DGRadius.lg)
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
        dayFormatter.string(from: date).uppercased()
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
