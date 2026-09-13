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
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var barKg: Double
    @State private var collarsKg: Double
    @State private var availableEquipment: Set<String>
    @State private var plateRows: [PlateRowDraft]

    private static let standardWeightsKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    init(profile: EquipmentProfileInfo, isNew: Bool = false, onDelete: (() -> Void)? = nil) {
        self.profile = profile
        self.isNew = isNew
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
        _barKg = State(initialValue: profile.barKg)
        _collarsKg = State(initialValue: profile.collarsKg)
        _availableEquipment = State(initialValue: Set(profile.availableEquipment))
        let existing = Dictionary(uniqueKeysWithValues: profile.plateStock.map { ($0.weightKg, $0.count) })
        _plateRows = State(
            initialValue: Self.standardWeightsKg.map { PlateRowDraft(weightKg: $0, count: existing[$0] ?? 0) }
        )
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
                    if !isNew, let onDelete {
                        deleteButton(onDelete)
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
    }

    private var navRow: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(DGFont.condensedLabel(13))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink3)
            Spacer()
            Text(isNew ? "New Profile" : "Edit Profile")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.plain)
                .font(DGFont.condensedLabel(13))
                .tracking(1.2)
                .textCase(.uppercase)
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
                .frame(height: 52)
                .dgCard(padding: 0)
        }
    }

    private var barCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Bar").dgLabel()
            VStack(spacing: 0) {
                stepperRow(label: "Bar weight", value: $barKg, range: 5...30, step: 0.5, suffix: "kg")
                Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                stepperRow(label: "Collars", value: $collarsKg, range: 0...5, step: 0.5, suffix: "kg")
            }
            .dgCard(padding: 0)
        }
    }

    private var plateCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Plate Inventory").dgLabel()
            VStack(spacing: 0) {
                ForEach(Array(plateRows.enumerated()), id: \.element.weightKg) { index, row in
                    plateRow(index: index, row: row)
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
        label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String
    ) -> some View {
        HStack {
            Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(Self.formatted(value.wrappedValue)) \(suffix)")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func plateRow(index: Int, row: PlateRowDraft) -> some View {
        HStack {
            Text("\(Self.formatted(row.weightKg)) kg").font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Stepper(value: countBinding(index: index), in: 0...40, step: 2) {
                Text("×\(plateRows[index].count)").font(DGFont.subhead).foregroundStyle(DGColor.ink3)
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func countBinding(index: Int) -> Binding<Int> {
        Binding(get: { plateRows[index].count }, set: { plateRows[index].count = $0 })
    }

    private func equipmentRow(_ option: EquipmentOption) -> some View {
        HStack {
            Text(option.title).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Toggle("", isOn: equipmentBinding(option))
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
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stock = plateRows.filter(\.isStocked).map { PlateStock(weightKg: $0.weightKg, count: $0.count) }
        if isNew {
            store.createProfile(
                name: trimmed, isActive: false, barKg: barKg, availableEquipment: Array(availableEquipment),
                plateStock: stock, collarsKg: collarsKg
            )
        } else {
            let draft = EquipmentProfileDraft(
                name: trimmed, barKg: barKg, availableEquipment: Array(availableEquipment),
                plateStock: stock, collarsKg: collarsKg
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

#Preview {
    if let store = PreviewStore.make() {
        EquipmentSeeder.seedIfNeeded(store: store)
        let profile = store.activeProfile() ?? EquipmentProfileInfo(
            id: UUID(), name: "Gym", isActive: true, barKg: 20, availableEquipment: [],
            plateStock: PlateStock.standardKg, collarsKg: 0
        )
        return AnyView(EquipmentProfileView(profile: profile).environment(store))
    }
    return AnyView(EmptyView())
}
