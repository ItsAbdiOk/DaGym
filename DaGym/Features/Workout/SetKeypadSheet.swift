import GymCore
import SwiftUI

/// The redesign's keypad for a loaded set: "Barbell Bench Press · set 2" with the plate maths
/// beside it, three fields (WEIGHT KG / REPS / RPE — the selected one wears the accent
/// border), a one-line hint, a 3×4 keypad and a ± / "Log set" row. Never the system keyboard.
///
/// Every value is bound canonically — kg, raw reps, an `Effort` — and converted to the
/// display unit at the edges, as `WeightKeypadSheet` (the single-field keypad for cardio and
/// bodyweight) always has. "Log set" completes an open set, so a lifter can type all three
/// numbers and log in one go; the RPE cell on the row still opens the plain-language picker.
struct SetKeypadSheet: View {
    enum Field: Hashable {
        case weight, reps, effort
    }

    var exercise: ExerciseInfo
    var set: SetEntry
    var setNumber: Int
    var initialField: Field
    var effortScale: Effort.Scale
    @Binding var weight: Double
    @Binding var reps: Double
    @Binding var effort: Effort?
    /// The active equipment profile for the plate line (see `PlateChip.inventory`).
    var inventory: ProgressionEquipment?
    /// "Log set", with the effort as typed (nil when the field was left alone).
    var onLog: (Effort?) -> Void

    // Internal, not private: the display, stepping and typing logic lives in
    // `SetKeypadSheet+Input.swift`.
    @State var field: Field
    @State var buffer = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) var preferences

    init(
        exercise: ExerciseInfo, set: SetEntry, setNumber: Int, initialField: Field,
        effortScale: Effort.Scale, weight: Binding<Double>, reps: Binding<Double>,
        effort: Binding<Effort?>, inventory: ProgressionEquipment? = nil, onLog: @escaping (Effort?) -> Void
    ) {
        self.exercise = exercise
        self.set = set
        self.setNumber = setNumber
        self.initialField = initialField
        self.effortScale = effortScale
        _weight = weight
        _reps = reps
        _effort = effort
        self.inventory = inventory
        self.onLog = onLog
        _field = State(initialValue: initialField)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            fieldsRow.padding(.top, DGSpace.s3)
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(DGColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            keyGrid.padding(.top, DGSpace.s3)
            actionRow.padding(.top, DGSpace.s2)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.top, DGSpace.s6)
        .padding(.bottom, DGSpace.s6)
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.bgBase)
        .presentationCornerRadius(DGRadius.xl)
        .dgDenseType()
    }

    /// Handle + title + fields + hint + four key rows + the action row.
    static let sheetHeight: CGFloat = 486

    // MARK: Title + fields

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(exercise.name) · set \(setNumber)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let plateText {
                Text(plateText.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(plateText.isLoadable ? DGColor.ink3 : DGColor.danger)
                    .lineLimit(1)
                    .fixedSize()
                    .onChange(of: plateText.isLoadable) { _, loadable in
                        if !loadable { Haptics.invalid() }
                    }
            }
        }
    }

    private var fieldsRow: some View {
        HStack(spacing: DGSpace.s2) {
            fieldTile(.weight, kicker: "Weight \(preferences.unitSymbol)", value: weightText)
            fieldTile(.reps, kicker: "Reps", value: repsText)
            fieldTile(.effort, kicker: effortScale == .rpe ? "RPE" : "RIR", value: effortText)
        }
    }

    private func fieldTile(_ target: Field, kicker: String, value: String) -> some View {
        let selected = field == target
        return Button {
            select(target)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(kicker).dgLabel()
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DGSpace.s3)
            .padding(.vertical, 11)
            .dgTile(radius: DGRadius.md, opacity: selected ? 0.85 : 0.55)
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    .strokeBorder(selected ? DGColor.coral : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(kicker)
        .accessibilityValue(value)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ target: Field) {
        guard target != field else { return }
        field = target
        buffer = ""
    }

    // MARK: Keys

    private var keyGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DGSpace.s2), count: 3)
        return LazyVGrid(columns: columns, spacing: DGSpace.s2) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { key in
                SetKeypadKey(label: key) { tap(key) }
                    .accessibilityIdentifier(A11yID.keypadKey(key))
            }
            SetKeypadKey(label: ".", accessibilityLabel: "Decimal point") { tap(".") }
            SetKeypadKey(label: "0") { tap("0") }
                .accessibilityIdentifier(A11yID.keypadKey("0"))
            SetKeypadKey(symbol: "delete.left", accessibilityLabel: "Delete") { backspace() }
        }
    }

    private var actionRow: some View {
        // Two step keys on the left half, "Log set" on the right — the prototype's 1 : 1 : 1.6.
        HStack(spacing: DGSpace.s2) {
            HStack(spacing: DGSpace.s2) {
                stepButton(sign: "−", label: "Decrease by \(stepLabel)") { step(by: -stepAmount) }
                stepButton(sign: "+", label: "Increase by \(stepLabel)") { step(by: stepAmount) }
            }
            .frame(maxWidth: .infinity)
            Button {
                onLog(effort)
                dismiss()
            } label: {
                Text("Log set")
                    .font(DGFont.condensedLabel(15))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background(
                        DGColor.coral, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    )
            }
            .buttonStyle(.dgControl)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(A11yID.keypadLog)
        }
    }

    private func stepButton(sign: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(sign) \(stepLabel)")
                .font(DGFont.condensedLabel(15))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .dgInkPill(radius: DGRadius.md, opacity: 0.06)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(label)
    }
}

/// One white keypad key: 22 pt medium, a flat white tile with a 1 pt shadow.
struct SetKeypadKey: View {
    var label: String?
    var symbol: String?
    var accessibilityLabel: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                } else {
                    Text(label ?? "").font(.system(size: 22, weight: .medium)).monospacedDigit()
                }
            }
            .foregroundStyle(DGColor.ink1)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .dgTile(radius: DGRadius.md, opacity: 0.8)
            .shadow(color: Color(hex: 0x3C2814).opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(accessibilityLabel ?? label ?? "")
    }
}

#Preview {
    @Previewable @State var weight = 72.5
    @Previewable @State var reps = 8.0
    @Previewable @State var effort: Effort? = Effort(rpe: 8)
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SetKeypadSheet(
                exercise: SampleData.bench, set: SetEntry(weightKg: 72.5, reps: 8), setNumber: 2,
                initialField: .weight, effortScale: .rpe, weight: $weight, reps: $reps, effort: $effort,
                onLog: { _ in }
            )
        }
        .environment(Preferences())
}
