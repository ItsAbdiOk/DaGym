import GymCore
import SwiftUI

/// Editor for one `EquipmentProfileInfo`: name, bar weight, plate inventory
/// (count steppers over the standard kg plate sizes) and which equipment
/// kinds are available. Used both for editing an existing profile and,
/// via `isNew`, for creating one.
struct EquipmentProfileView: View {
    var profile: EquipmentProfileInfo
    var isNew: Bool
    var onDelete: (() -> Void)?

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var barKg: Double
    @State private var collarsKg: Double
    @State private var availableEquipment: Set<String>
    @State private var machineSelection: MachineSelection
    @State private var plateRows: [PlateRowDraft] = []

    /// The plate sizes already saved on this profile, with their counts. Kept as a list rather
    /// than a `[Double: Int]` because kg keys never match lb ones exactly (45 lb is
    /// 20.4116… kg): an lb lifter opening the kg-seeded "Gym" found every count reading 0 and
    /// silently wiped the profile's plates on Save. `plateRows` now shows the union of this
    /// profile's own sizes and the standard set for the lifter's unit.
    private let existingPlates: [PlateStock]

    init(profile: EquipmentProfileInfo, isNew: Bool = false, onDelete: (() -> Void)? = nil) {
        self.profile = profile
        self.isNew = isNew
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
        _barKg = State(initialValue: profile.barKg)
        _collarsKg = State(initialValue: profile.collarsKg)
        _availableEquipment = State(initialValue: Set(profile.availableEquipment))
        _machineSelection = State(initialValue: MachineSelection(profile: profile))
        existingPlates = profile.plateStock
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s5) {
                    navRow
                    nameCard
                    barCard
                    plateCard
                    equipmentCard
                    MachinesCard(types: availableEquipment, selection: $machineSelection)
                    if !isNew, let onDelete {
                        deleteButton(onDelete)
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task {
            guard plateRows.isEmpty else { return }
            plateRows = EquipmentStep.rows(
                standard: EquipmentStep.standardWeightsKg(for: preferences.weightUnit),
                existing: existingPlates
            ).map { PlateRowDraft(weightKg: $0.weightKg, count: $0.count) }
        }
    }

    private var navRow: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .foregroundStyle(DGColor.ink3)
            Spacer()
            Text(isNew ? "New Profile" : "Edit Profile")
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .foregroundStyle(canSave ? DGColor.coralText : DGColor.ink4)
                .disabled(!canSave)
        }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Name").dgLabel()
            TextField("Profile name", text: $name)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .padding(.horizontal, DGSpace.s5)
                .frame(minHeight: 52)
                .dgCard(padding: 0)
        }
    }

    private var barCard: some View {
        let unit = preferences.weightUnit
        return VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Bar").dgLabel()
            VStack(spacing: 0) {
                stepperRow(label: "Bar weight", value: $barKg, range: 5...30, step: stepKg(unit), unit: unit)
                Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                stepperRow(label: "Collars", value: $collarsKg, range: 0...5, step: stepKg(unit), unit: unit)
            }
            .dgCard(padding: 0)
        }
    }

    private func stepKg(_ unit: WeightUnit) -> Double { EquipmentStep.stepKg(for: unit) }

    private var plateCard: some View {
        let unit = preferences.weightUnit
        return VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Plate Inventory").dgLabel()
            VStack(spacing: 0) {
                // Keyed on position, not `weightKg`: the rows are fixed once `.task` builds
                // them, and `Double` ids from a migrated profile were not guaranteed unique.
                ForEach(Array(plateRows.enumerated()), id: \.offset) { index, row in
                    plateRow(index: index, row: row, unit: unit)
                    if index < plateRows.count - 1 {
                        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                    }
                }
            }
            .dgCard(padding: 0)
            Text("Count is total plates, not pairs.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var equipmentCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Available Equipment").dgLabel()
            VStack(spacing: 0) {
                ForEach(Array(EquipmentOption.allCases.enumerated()), id: \.element.id) { index, option in
                    equipmentRow(option)
                    if index < EquipmentOption.allCases.count - 1 {
                        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                    }
                }
            }
            .dgCard(padding: 0)
        }
    }

    private func stepperRow(
        label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: WeightUnit
    ) -> some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(unit.format(kg: value.wrappedValue)) \(unit.symbol)")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            .accessibilityLabel(label)
            .accessibilityValue("\(unit.format(kg: value.wrappedValue)) \(unit.symbol)")
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func plateRow(index: Int, row: PlateRowDraft, unit: WeightUnit) -> some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            Text("\(unit.format(kg: row.weightKg)) \(unit.symbol)")
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Stepper(value: countBinding(index: index), in: 0...40, step: 2) {
                Text("×\(plateRows[index].count)").font(DGFont.subhead).foregroundStyle(DGColor.ink3)
            }
            .accessibilityLabel("\(unit.format(kg: row.weightKg)) \(unit.symbol) plates")
            .accessibilityValue("\(plateRows[index].count)")
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func countBinding(index: Int) -> Binding<Int> {
        Binding(get: { plateRows[index].count }, set: { plateRows[index].count = $0 })
    }

    private func equipmentRow(_ option: EquipmentOption) -> some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            Text(option.title).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Toggle(option.title, isOn: equipmentBinding(option))
                .labelsHidden()
                .tint(DGColor.coral)
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func equipmentBinding(_ option: EquipmentOption) -> Binding<Bool> {
        Binding(
            get: { availableEquipment.contains(option.rawValue) },
            set: { isOn in
                if isOn {
                    availableEquipment.insert(option.rawValue)
                } else {
                    availableEquipment.remove(option.rawValue)
                }
            }
        )
    }

    private func deleteButton(_ onDelete: @escaping () -> Void) -> some View {
        Button {
            onDelete()
            dismiss()
        } label: {
            Text("Delete Profile")
                .font(DGFont.condensedLabel(15))
                .foregroundStyle(DGColor.danger)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.dgCard)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stock = plateRows.filter(\.isStocked).map { PlateStock(weightKg: $0.weightKg, count: $0.count) }
        if isNew {
            store.createProfile(
                name: trimmed, isActive: false, barKg: barKg, availableEquipment: Array(availableEquipment),
                plateStock: stock, collarsKg: collarsKg,
                restrictsMachines: machineSelection.restrictsMachinesForSave,
                availableMachines: machineSelection.availableMachinesForSave
            )
        } else {
            let draft = EquipmentProfileDraft(
                name: trimmed, barKg: barKg, availableEquipment: Array(availableEquipment),
                plateStock: stock, collarsKg: collarsKg,
                restrictsMachines: machineSelection.restrictsMachinesForSave,
                availableMachines: machineSelection.availableMachinesForSave
            )
            store.updateProfile(id: profile.id, draft: draft)
        }
        dismiss()
    }
}

private struct PlateRowDraft {
    var weightKg: Double
    var count: Int

    // `count` is a plate quantity, not a Collection.count.
    // swiftlint:disable:next empty_count
    var isStocked: Bool { count > 0 }
}

/// Unit-aware sizing for this screen's steppers, pulled out so it's testable without SwiftUI.
enum EquipmentStep {
    /// The plate sizes offered, in the lifter's unit: the standard kg set, or the standard
    /// 45/35/25/10/5/2.5 lb set converted to kg (`WeightUnit.plateStock`).
    static func standardWeightsKg(for unit: WeightUnit) -> [Double] {
        WeightUnit.plateStock(for: unit).map(\.weightKg)
    }

    /// A kg lifter keeps the existing half-kg bar/collar step; a lb lifter steps by a whole
    /// pound.
    static func stepKg(for unit: WeightUnit) -> Double {
        unit == .kg ? 0.5 : unit.toKg(1)
    }

    /// Two plate weights the editor should treat as the same row. Wide enough to absorb the
    /// float drift of a pound value stored in kg, far narrower than any real plate gap.
    static let sameSizeToleranceKg = 0.01

    /// The rows the editor shows: this profile's own plate sizes plus the standard set for the
    /// lifter's unit, heaviest first, each carrying the count already saved.
    ///
    /// Matching by exact kg value dropped every saved size that wasn't in the standard list for
    /// the *current* unit, and Save then wrote the profile back without them. Taking the union
    /// means an lb lifter can see and keep the kg plates a kg-seeded profile came with.
    ///
    /// Two saved sizes within the tolerance of each other (20.4116 and 20.4117 kg from a
    /// rounding change) collapse into one row carrying both counts, so no two rows share a size.
    static func rows(standard: [Double], existing: [PlateStock]) -> [PlateStock] {
        var rows: [PlateStock] = []
        for stock in existing {
            if let index = rows.firstIndex(where: {
                abs($0.weightKg - stock.weightKg) < sameSizeToleranceKg
            }) {
                rows[index].count += stock.count
            } else {
                rows.append(stock)
            }
        }
        for weight in standard where !rows.contains(where: {
            abs($0.weightKg - weight) < sameSizeToleranceKg
        }) {
            rows.append(PlateStock(weightKg: weight, count: 0))
        }
        return rows.sorted { $0.weightKg > $1.weightKg }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        EquipmentSeeder.seedIfNeeded(store: store)
        let profile = store.activeProfile() ?? EquipmentProfileInfo(
            id: UUID(), name: "Gym", isActive: true, barKg: 20, availableEquipment: [],
            plateStock: PlateStock.standardKg, collarsKg: 0
        )
        return AnyView(
            EquipmentProfileView(profile: profile).environment(store).environment(Preferences())
        )
    }
    return AnyView(EmptyView())
}
