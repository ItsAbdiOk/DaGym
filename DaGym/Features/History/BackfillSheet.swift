import SwiftUI

/// "Log a past workout" — pick when it happened (never in the future — a future date would
/// count toward this week's goal), then choose freestyle or a routine. Detent-sized glass
/// sheet, ~420 pt. When `routines` is non-empty, "Use a Routine" opens a menu to pick which one.
struct BackfillSheet: View {
    var routines: [RoutineInfo]
    var onFreestyle: (Date, Int) -> Void
    var onRoutine: (Date, Int, UUID) -> Void

    @State private var date = Date()
    @State private var startTime = Date()
    @State private var durationMinutes = 55

    private static let durationOptions = [30, 40, 45, 50, 55, 60, 75, 90]

    init(
        routines: [RoutineInfo] = [], onFreestyle: @escaping (Date, Int) -> Void,
        onRoutine: @escaping (Date, Int, UUID) -> Void
    ) {
        self.routines = routines
        self.onFreestyle = onFreestyle
        self.onRoutine = onRoutine
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
                    onFreestyle(combined, durationMinutes)
                } label: {
                    Text("Freestyle")
                        .font(DGFont.condensedLabel(15))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .dgGlass(.regular, radius: DGRadius.lg)
                }
                .buttonStyle(DGPressStyle())
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
    }

    /// A menu of `routines`; hidden when there's nothing to pick from (a routine-less backfill
    /// would resolve to an untitled session).
    @ViewBuilder
    private var routineButton: some View {
        if !routines.isEmpty {
            Menu {
                ForEach(routines) { routine in
                    Button(routine.name) { onRoutine(combined, durationMinutes, routine.id) }
                }
            } label: {
                Text("Use a Routine")
                    .font(DGFont.condensedLabel(15))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
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

/// One labelled row inside the fields card, with the control styled as a pill.
private struct FieldRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(title)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            control
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 34)
                .background(DGColor.surface3, in: Capsule())
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(height: 56)
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            BackfillSheet(onFreestyle: { _, _ in }, onRoutine: { _, _, _ in })
        }
}
