import GymCore
import SwiftData
import SwiftUI

/// "Schedule" — a routine per weekday, plus a look-ahead strip for moving an
/// individual session to another date. Reachable from the calendar icon in
/// `RoutinesTabView`'s header (plan.md §6.1). Saves after every change and,
/// when `Preferences.calendarSyncEnabled` is on, mirrors the plan onto the
/// "DaGym" calendar via `CalendarSyncService` (plan.md §6.8).
struct ScheduleView: View {
    var onDone: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var routines: [RoutineInfo] = []
    @State private var schedule = WeeklySchedule()
    @State private var moveRequest: MoveRequest?
    @State private var eventStore: EventStoring = EventKitStore()

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    navRow
                    weekdayCard
                    thisWeekCard
                    footnote
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .task { refresh() }
        .sheet(item: $moveRequest) { request in
            MoveSessionSheet(request: request, calendar: .current, onMove: { performMove(request, to: $0) })
        }
    }

    private var navRow: some View {
        HStack {
            Button("Close", action: onDone)
                .buttonStyle(.plain)
                .dgLabel()
            Spacer()
            Text("Schedule")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Color.clear.frame(width: 44, height: 1)
        }
    }

    private var weekdayCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Weekly Plan").dgLabel()
            VStack(spacing: 0) {
                ForEach(Array(orderedWeekdays.enumerated()), id: \.element) { index, weekday in
                    WeekdayRow(
                        weekday: weekday, routines: routines, selectedRoutineID: schedule.days[weekday],
                        onSelect: { setDay(weekday, to: $0) }
                    )
                    if index != orderedWeekdays.count - 1 {
                        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                    }
                }
            }
            .dgCard(padding: 0)
        }
    }

    private var thisWeekCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("This Week").dgLabel()
            VStack(spacing: 0) {
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    ThisWeekRow(date: date, routine: routine(on: date), onMove: { beginMove(date: date) })
                    if index != weekDates.count - 1 {
                        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                    }
                }
            }
            .dgCard(padding: 0)
        }
    }

    private var footnote: some View {
        Text(
            preferences.calendarSyncEnabled
                ? "Synced to your \"DaGym\" calendar."
                : "Turn on calendar sync in Settings → Calendar to keep these sessions on your calendar."
        )
        .font(DGFont.footnote)
        .foregroundStyle(DGColor.ink4)
    }

    private var orderedWeekdays: [Weekday] { Weekday.ordered(mondayFirst: preferences.weekStartsMonday) }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private func routine(on date: Date) -> RoutineInfo? {
        guard let routineID = schedule.routineID(on: date, calendar: .current) else { return nil }
        return routines.first { $0.id == routineID }
    }

    private func refresh() {
        routines = store.routines()
        schedule = store.schedule()
    }

    private func setDay(_ weekday: Weekday, to routineID: UUID?) {
        schedule.days[weekday] = routineID
        persist()
    }

    private func beginMove(date: Date) {
        guard let routine = routine(on: date) else { return }
        moveRequest = MoveRequest(sourceDate: date, routineID: routine.id, routineName: routine.name)
    }

    private func performMove(_ request: MoveRequest, to newDate: Date) {
        schedule.moved(date: request.sourceDate, to: nil)
        schedule.moved(date: newDate, to: request.routineID)
        persist()
    }

    private func persist() {
        store.saveSchedule(schedule)
        guard preferences.calendarSyncEnabled else { return }
        let snapshot = schedule
        let currentRoutines = routines
        let hour = preferences.scheduledStartHour
        let existingEventIDs = store.scheduleEventIDs()
        Task {
            let service = CalendarSyncService(eventStore: eventStore)
            let request = ScheduleSyncRequest(
                schedule: snapshot, routines: currentRoutines, startDate: Date(), defaultStartHour: hour,
                existingEventIDs: existingEventIDs
            )
            guard let updated = try? await service.sync(request) else { return }
            store.saveScheduleEventIDs(updated)
        }
    }
}

/// A pending "move this session to a new date" request, presented as a sheet.
private struct MoveRequest: Identifiable {
    let id = UUID()
    var sourceDate: Date
    var routineID: UUID
    var routineName: String
}

/// One weekday row: label plus a menu picking a routine or "Rest".
private struct WeekdayRow: View {
    var weekday: Weekday
    var routines: [RoutineInfo]
    var selectedRoutineID: UUID?
    var onSelect: (UUID?) -> Void

    var body: some View {
        HStack {
            Text(weekday.displayName)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Menu {
                Button("Rest") { onSelect(nil) }
                ForEach(routines) { routine in
                    Button(routine.name) { onSelect(routine.id) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedName)
                        .font(DGFont.subhead)
                        .foregroundStyle(selectedRoutineID == nil ? DGColor.ink3 : DGColor.ink1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: DGTap.rowHeight)
    }

    private var selectedName: String {
        guard let selectedRoutineID else { return "Rest" }
        return routines.first { $0.id == selectedRoutineID }?.name ?? "Rest"
    }
}

/// One "this week" row: date, planned routine (or rest), and a "Move…" action.
private struct ThisWeekRow: View {
    var date: Date
    var routine: RoutineInfo?
    var onMove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dayLabel(date)).dgLabel()
                Text(routine?.name ?? "Rest")
                    .font(DGFont.subhead)
                    .foregroundStyle(routine == nil ? DGColor.ink3 : DGColor.ink1)
            }
            Spacer()
            if routine != nil {
                Button("Move…", action: onMove)
                    .buttonStyle(.plain)
                    .font(DGFont.condensedLabel(12))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.coralText)
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: DGTap.rowHeight)
    }

    private static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date).uppercased()
    }
}

/// Glass sheet: pick a new date for a planned session.
private struct MoveSessionSheet: View {
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
                Text("Move Session")
                    .font(DGFont.title2)
                    .textCase(.uppercase)
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
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.hidden)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        ScheduleView(onDone: {})
            .environment(WorkoutStore(context: container.mainContext))
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
