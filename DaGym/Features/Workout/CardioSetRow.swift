import GymCore
import SwiftUI

/// One cardio set (plan.md §6.1): badge · start · time · distance · incline · done, with the
/// derived pace and speed on a second line. No weight, no reps. Same 56 pt height, fonts, tints
/// and swipe-to-reveal as `SetRow`; the ▶ opens the count-up timer `TimedHoldCard` runs, and
/// tapping the time or distance types it on the keypad instead.
struct CardioSetRow: View {
    var setEntry: SetEntry
    var badgeIndex: Int
    var rowIndex: Int
    var isCurrent: Bool
    /// Show the incline field: treadmill/stair exercises, or once the lifter revealed it.
    var showsIncline: Bool
    var onStart: () -> Void
    var onTapTime: () -> Void
    var onTapDistance: () -> Void
    var onTapIncline: () -> Void
    var onToggleDone: () -> Void
    var onDelete: () -> Void = {}
    var onChangeKind: (SetKind) -> Void = { _ in }

    @State private var isSwipeOpen = false
    @State private var showKindPicker = false
    @Environment(Preferences.self) private var preferences

    private static let swipeButtonWidth: CGFloat = 52
    private static let actionsWidth = swipeButtonWidth * 2

    var body: some View {
        SwipeToRevealRow(actionsWidth: Self.actionsWidth, isOpen: $isSwipeOpen) {
            rowContent
        } actions: {
            swipeActions
        }
        .confirmationDialog("Change set type", isPresented: $showKindPicker, titleVisibility: .visible) {
            ForEach(SetKind.allCases, id: \.self) { kind in
                Button(kind.displayName) {
                    onChangeKind(kind)
                    isSwipeOpen = false
                }
            }
        }
    }

    private var unit: DistanceUnit { preferences.distanceUnit }
    /// A value the lifter hasn't logged yet is a target: dimmer, like a timed hold's.
    private var isLogged: Bool {
        setEntry.isDone || setEntry.durationSeconds != nil || setEntry.distanceMeters != nil
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DGSpace.s3) {
                SetKindBadge(kind: setEntry.kind, index: badgeIndex)
                if !setEntry.isDone { startButton }
                metric(timeText, label: "Time", value: timeText, action: onTapTime)
                metric(distanceText, label: "Distance", value: distanceValue, action: onTapDistance)
                if showsIncline {
                    metric(inclineText, label: "Incline", value: inclineText, action: onTapIncline)
                }
                Spacer(minLength: 0)
                doneButton
            }
            if let paceLine {
                Text(paceLine)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .accessibilityLabel("Pace and speed, \(paceLine)")
                    .padding(.leading, 28 + DGSpace.s3)
                    .padding(.bottom, DGSpace.s1)
            }
        }
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: DGTap.rowHeight)
        .background(rowFill, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                .strokeBorder(DGColor.coral, lineWidth: isCurrent ? 1 : 0)
        }
        .dgDenseType()
    }

    private func metric(
        _ text: String, label: String, value: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .dgMetric(DGFont.metricM)
                .foregroundStyle(metricColor)
                .frame(minWidth: 44, alignment: .leading)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var startButton: some View {
        Button(action: onStart) {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isCurrent ? DGColor.inkOnCoral : DGColor.ink2)
                .frame(width: 28, height: 28)
                .background(isCurrent ? DGColor.coral : DGColor.surface3, in: Circle())
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Start timer")
    }

    private var doneButton: some View {
        Button(action: onToggleDone) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(setEntry.isDone ? DGColor.success : DGColor.ink4)
                .frame(width: DGTap.done, height: DGTap.done)
                .background(
                    setEntry.isDone ? DGColor.success.opacity(0.22) : DGColor.surface3,
                    in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
        }
        .buttonStyle(.dgControl)
        .accessibilityIdentifier(A11yID.setRowDone(rowIndex))
        .accessibilityLabel(doneButtonLabel)
        .accessibilityAddTraits(setEntry.isDone ? .isSelected : [])
        .accessibilityAction(named: "Delete set", onDelete)
        .accessibilityAction(named: "Change set type") { showKindPicker = true }
    }

    private var doneButtonLabel: String {
        SetRowAccessibility.cardioLabel(
            kind: setEntry.kind, summary: setEntry.cardioSummary(unit: unit),
            done: setEntry.isDone, isCurrent: isCurrent
        )
    }

    private var swipeActions: some View {
        HStack(spacing: 0) {
            swipeButton(
                symbol: "arrow.triangle.2.circlepath", tint: DGColor.setSuperset, fill: DGColor.surface3,
                label: "Change set type"
            ) {
                showKindPicker = true
            }
            swipeButton(
                symbol: "trash", tint: .white, fill: DGColor.danger, label: "Delete set", action: onDelete
            )
        }
    }

    private func swipeButton(
        symbol: String, tint: Color, fill: Color, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: Self.swipeButtonWidth)
                .frame(minHeight: DGTap.rowHeight)
                .background(fill)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(label)
    }

    // MARK: Text

    private var timeText: String { setEntry.cardioSeconds.map(CardioPace.clock) ?? "–" }

    private var distanceText: String { setEntry.cardioMeters.map { unit.format(meters: $0) } ?? "–" }

    private var distanceValue: String {
        setEntry.cardioMeters.map { unit.formatWithSymbol(meters: $0) } ?? "no distance"
    }

    private var inclineText: String {
        guard let incline = setEntry.inclinePercent else { return "–%" }
        return "\(WorkoutSession.format(incline))%"
    }

    /// "5:06 /km · 11.8 km/h" once both a time and a distance are on the row.
    private var paceLine: String? {
        Self.paceLine(setEntry: setEntry, unit: unit)
    }

    /// Pure so the formatting is testable without rendering: nil until both numbers exist.
    static func paceLine(setEntry: SetEntry, unit: DistanceUnit) -> String? {
        guard let pace = setEntry.cardioPace(unit: unit), let speed = setEntry.cardioSpeed(unit: unit) else {
            return nil
        }
        return "\(pace) · \(speed)"
    }

    private var metricColor: Color {
        if isCurrent { return DGColor.coral }
        return isLogged ? DGColor.ink1 : DGColor.ink3
    }

    private var rowFill: Color {
        if setEntry.isDone { return DGColor.success.opacity(0.16) }
        return DGColor.surface2
    }
}

#Preview {
    VStack(spacing: DGSpace.s2) {
        CardioSetRow(
            setEntry: SetEntry(
                weightKg: 0, reps: 0, isDone: true, durationSeconds: 1530, distanceMeters: 5000,
                inclinePercent: 1
            ),
            badgeIndex: 1, rowIndex: 0, isCurrent: false, showsIncline: true,
            onStart: {}, onTapTime: {}, onTapDistance: {}, onTapIncline: {}, onToggleDone: {}
        )
        CardioSetRow(
            setEntry: SetEntry(weightKg: 0, reps: 0, targetSeconds: 1500, targetDistanceMeters: 5000),
            badgeIndex: 2, rowIndex: 1, isCurrent: true, showsIncline: false,
            onStart: {}, onTapTime: {}, onTapDistance: {}, onTapIncline: {}, onToggleDone: {}
        )
    }
    .padding()
    .background(DGColor.bgBase)
    .environment(Preferences())
}
