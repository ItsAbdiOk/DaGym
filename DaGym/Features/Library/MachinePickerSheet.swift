import GymCore
import SwiftUI

/// "Machine · Leg Press ›" — the form row `NewExerciseSheet` and `ExerciseSettingsSheet` show
/// when the equipment kind has stations, opening `MachinePickerSheet`. `machine` is the
/// `Machine` raw value stored on the exercise; nil is "any of this kind".
struct MachineFormRow: View {
    /// The exercise's equipment kind (`EquipmentOption` raw value); only its stations are offered.
    var equipmentType: String
    @Binding var machine: String?
    @State private var isPicking = false

    /// Whether this kind has stations to pick from at all.
    static func applies(to equipmentType: String) -> Bool {
        Machine.equipmentTypes.contains(equipmentType)
    }

    private var picked: Machine? { machine.flatMap(Machine.init(rawValue:)) }
    private var kindTitle: String {
        EquipmentOption(rawValue: equipmentType)?.title.lowercased() ?? equipmentType
    }

    var body: some View {
        Button {
            isPicking = true
        } label: {
            HStack(spacing: DGSpace.s3) {
                Text("Machine").dgLabel().frame(minWidth: 90, alignment: .leading)
                if let picked { MachineThumbnailView(machine: picked, size: 32) }
                Text(picked?.displayName ?? "Any \(kindTitle)")
                    .font(DGFont.body)
                    .foregroundStyle(picked == nil ? DGColor.ink3 : DGColor.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DGSpace.s3)
            .padding(.horizontal, DGSpace.s5)
        }
        .buttonStyle(.dgRow)
        .accessibilityLabel("Machine")
        .accessibilityValue(picked?.displayName ?? "Any")
        .sheet(isPresented: $isPicking) {
            MachinePickerSheet(equipmentType: equipmentType, machine: $machine)
        }
    }
}

/// Every station of one kind with its picture, searchable by the labels on the machine
/// (`Machine.aliases`), plus "Any" to clear. Picking dismisses.
struct MachinePickerSheet: View {
    var equipmentType: String
    @Binding var machine: String?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var machines: [Machine] {
        Machine.machines(ofType: equipmentType).filter { $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(spacing: 0) {
                        anyRow
                        ForEach(machines, id: \.rawValue) { station in
                            Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                            row(station)
                        }
                    }
                    .dgCard(padding: 0)
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.vertical, DGSpace.s3)
                }
            }
            .navigationTitle("Machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Pec fly, Gravitron, cross trainer…")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
        .presentationCornerRadius(DGRadius.sheet)
    }

    private var anyRow: some View {
        Button {
            machine = nil
            dismiss()
        } label: {
            HStack(spacing: DGSpace.s3) {
                Text("Any \(EquipmentOption(rawValue: equipmentType)?.title.lowercased() ?? equipmentType)")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if machine == nil { checkmark }
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 52)
        }
        .buttonStyle(.dgRow)
    }

    private func row(_ station: Machine) -> some View {
        Button {
            machine = station.rawValue
            dismiss()
        } label: {
            HStack(spacing: DGSpace.s3) {
                MachineThumbnailView(machine: station)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.displayName).font(DGFont.body).foregroundStyle(DGColor.ink1)
                    Text(station.aliases.prefix(3).joined(separator: " · "))
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink4)
                        .lineLimit(1)
                }
                Spacer()
                if machine == station.rawValue { checkmark }
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 60)
        }
        .buttonStyle(.dgRow)
        .accessibilityLabel(station.displayName)
        .accessibilityAddTraits(machine == station.rawValue ? .isSelected : [])
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(DGColor.coralText)
            .accessibilityHidden(true)
    }
}
