import SwiftUI

/// "Log a past workout" — pick when it happened (never in the future — a future date would
/// count toward this week's goal), then choose freestyle or a routine. Detent-sized glass
/// sheet, ~420 pt. When `routines` is non-empty, "Use a Routine" opens a menu to pick which one.
/// When `records` already has a workout on the chosen day, a Replace / Keep both / Cancel
/// choice comes first; Replace hands the day's workout ids to `onReplace` before starting.
struct BackfillSheet: View {
    var routines: [RoutineInfo]
    var records: [WorkoutRecord]
    var onFreestyle: (Date, Int) -> Void
    var onRoutine: (Date, Int, UUID) -> Void
    var onReplace: ([UUID]) -> Void

    @State private var date: Date
    @State private var startTime = Date()
    @State private var durationMinutes = 55
    @State private var conflict: BackfillConflict?

    private static let durationOptions = [30, 40, 45, 50, 55, 60, 75, 90]

    init(
        routines: [RoutineInfo] = [], initialDate: Date = Date(), records: [WorkoutRecord] = [],
        onFreestyle: @escaping (Date, Int) -> Void, onRoutine: @escaping (Date, Int, UUID) -> Void,
        onReplace: @escaping ([UUID]) -> Void = { _ in }
    ) {
        self.routines = routines
        self.records = records
        self.onFreestyle = onFreestyle
        self.onRoutine = onRoutine
        self.onReplace = onReplace
        _date = State(initialValue: min(initialDate, Date()))
    }

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Log a Past Workout")
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text("Pick when it happened; you'll fill in the sets next.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            fieldsCard
            HStack(spacing: DGSpace.s3) {
                Button {
                    begin(.freestyle)
                } label: {
                    Text("Freestyle")
                        .font(DGFont.condensedLabel(15))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .dgGlass(.regular, radius: DGRadius.lg)
                }
                .buttonStyle(.dgControl)
                routineButton
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.hidden)
        .confirmationDialog(
            "Already Logged That Day", isPresented: conflictBinding, titleVisibility: .visible,
            presenting: conflict
        ) { pending in
            Button("Replace", role: .destructive) { resolve(pending, choice: .replace) }
            Button("Keep Both") { resolve(pending, choice: .keepBoth) }
            Button("Cancel", role: .cancel) { conflict = nil }
        } message: { pending in
            Text(BackfillConflict.message(for: pending.existing))
        }
    }

    private var conflictBinding: Binding<Bool> {
        Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })
    }

    /// Starts straight away when the day is free; otherwise parks the choice in `conflict`
    /// until the dialog resolves it.
    private func begin(_ start: BackfillConflict.Start) {
        let existing = BackfillConflict.workouts(on: combined, in: records)
        guard existing.isEmpty else {
            conflict = BackfillConflict(existing: existing, start: start)
            return
        }
        run(start)
    }

    private func resolve(_ pending: BackfillConflict, choice: BackfillConflict.Choice) {
        conflict = nil
        if choice == .replace { onReplace(pending.existing.map(\.id)) }
        run(pending.start)
    }

    private func run(_ start: BackfillConflict.Start) {
        switch start {
        case .freestyle: onFreestyle(combined, durationMinutes)
        case .routine(let id): onRoutine(combined, durationMinutes, id)
        }
    }

    /// A menu of `routines`; hidden when there's nothing to pick from (a routine-less backfill
    /// would resolve to an untitled session).
    @ViewBuilder
    private var routineButton: some View {
        if !routines.isEmpty {
            Menu {
                ForEach(routines) { routine in
                    Button(routine.name) { begin(.routine(routine.id)) }
                }
            } label: {
                Text("Use a Routine")
                    .font(DGFont.condensedLabel(15))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(DGColor.coral, in: Capsule())
                    .shadow(color: DGColor.coral.opacity(0.35), radius: 12, y: 6)
            }
        }
    }

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            FieldRow(title: "Date") {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Divider().overlay(DGColor.hairline)
            FieldRow(title: "Start time") {
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Divider().overlay(DGColor.hairline)
            FieldRow(title: "Duration") {
                Menu {
                    ForEach(Self.durationOptions, id: \.self) { minutes in
                        Button("\(minutes) min") { durationMinutes = minutes }
                    }
                } label: {
                    Text("\(durationMinutes) min")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink1)
                }
            }
        }
        .dgCard(padding: 0)
    }

    /// `date`'s calendar day merged with `startTime`'s clock time.
    private var combined: Date {
        let calendar = Calendar.current
        var merged = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: startTime)
        merged.hour = time.hour
        merged.minute = time.minute
        return calendar.date(from: merged) ?? date
    }
}

/// A backfill that landed on a day with workouts already logged, waiting on Replace /
/// Keep both / Cancel.
struct BackfillConflict: Identifiable {
    enum Start: Equatable {
        case freestyle
        case routine(UUID)
    }

    enum Choice: Equatable {
        case replace, keepBoth, cancel
    }

    let id = UUID()
    var existing: [WorkoutRecord]
    var start: Start

    /// Finished workouts logged on the same calendar day as `date`.
    static func workouts(
        on date: Date, in records: [WorkoutRecord], calendar: Calendar = .current
    ) -> [WorkoutRecord] {
        records.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// "Push A is already logged on that day." / "2 workouts are already logged on that day."
    static func message(for existing: [WorkoutRecord]) -> String {
        if existing.count == 1, let only = existing.first {
            return "\(only.title) is already logged on that day. Replace it, or keep both?"
        }
        return "\(existing.count) workouts are already logged on that day. Replace them, or keep both?"
    }
}

/// One labelled row inside the fields card, with the control styled as a pill.
private struct FieldRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control

    var body: some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            Text(title)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            control
                .accessibilityLabel(title)
                .padding(.horizontal, DGSpace.s3)
                .frame(minHeight: 34)
                .background(DGColor.surface3, in: Capsule())
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 56)
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            BackfillSheet(onFreestyle: { _, _ in }, onRoutine: { _, _, _ in })
        }
}
