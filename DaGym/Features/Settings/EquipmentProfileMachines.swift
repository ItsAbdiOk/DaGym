import GymCore
import SwiftUI

/// The "Machines at this gym" state behind `EquipmentProfileView`, kept as a value so the
/// toggle/All/None logic and the save mapping are testable without SwiftUI.
///
/// The set is kept over *every* station, not just those of the ticked kinds, so ticking
/// "Cable" back on shows the stations the way the lifter last left them. A selection that
/// covers every station saves as `restrictsMachines == false` ("all"), so a station added to
/// the taxonomy later shows up on its own instead of arriving unticked.
struct MachineSelection: Equatable {
    var restricts: Bool
    var machines: Set<Machine>

    init(restricts: Bool = false, machines: Set<Machine> = []) {
        self.restricts = restricts
        self.machines = machines
    }

    init(profile: EquipmentProfileInfo) {
        restricts = profile.restrictsMachines
        machines = Set(profile.availableMachines.compactMap(Machine.init(rawValue:)))
    }

    func isOn(_ machine: Machine) -> Bool { !restricts || machines.contains(machine) }

    mutating func set(_ machine: Machine, on: Bool) {
        if !restricts {
            machines = Set(Machine.allCases)
            restricts = true
        }
        if on { machines.insert(machine) } else { machines.remove(machine) }
    }

    /// Ticks or clears every station of `types` at once, leaving other kinds' stations alone.
    mutating func setAll(ofTypes types: Set<String>, on: Bool) {
        let affected = Machine.allCases.filter { types.contains($0.equipmentType) }
        if !restricts {
            machines = Set(Machine.allCases)
            restricts = true
        }
        if on { machines.formUnion(affected) } else { machines.subtract(affected) }
    }

    /// The stations of the ticked kinds, and how many are on — "14 of 26".
    func count(ofTypes types: Set<String>) -> (on: Int, total: Int) {
        let offered = Machine.allCases.filter { types.contains($0.equipmentType) }
        return (offered.filter(isOn).count, offered.count)
    }

    /// What `EquipmentProfileDraft` / `createProfile` store.
    var restrictsMachinesForSave: Bool { restricts && !machines.isSuperset(of: Machine.allCases) }
    var availableMachinesForSave: [String] {
        restrictsMachinesForSave ? Machine.allCases.filter(machines.contains).map(\.rawValue) : []
    }
}

/// The "Machines at this gym" card: every `Machine` of the ticked kinds, grouped by kind, each
/// a toggle with its picture, with All / None, a running count and a search field that matches
/// the labels on the machine itself (`Machine.aliases`). Hidden when no ticked kind has stations.
struct MachinesCard: View {
    /// The ticked equipment kinds (`EquipmentOption` raw values).
    var types: Set<String>
    @Binding var selection: MachineSelection
    @State private var query = ""

    private var shownTypes: [String] { Machine.equipmentTypes.filter(types.contains) }

    var body: some View {
        if !shownTypes.isEmpty {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                header
                searchField
                VStack(spacing: 0) {
                    ForEach(shownTypes, id: \.self) { type in
                        let machines = Machine.machines(ofType: type).filter { $0.matches(query) }
                        if !machines.isEmpty {
                            groupLabel(type)
                            ForEach(machines, id: \.rawValue) { machine in
                                machineRow(machine)
                                Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                            }
                        }
                    }
                }
                .dgCard(padding: 0)
                Text("Only the stations ticked here are offered in the library, routines and programs.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.ink4)
                .accessibilityHidden(true)
            TextField("Find a station (e.g. pec fly, Gravitron)", text: $query)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 44)
        .dgCard(padding: 0)
    }

    private var header: some View {
        let count = selection.count(ofTypes: Set(shownTypes))
        return HStack(spacing: DGSpace.s3) {
            Text("Machines at this gym").dgLabel()
            Text("\(count.on) of \(count.total)")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
                .accessibilityLabel("\(count.on) of \(count.total) stations selected")
            Spacer()
            Button("All") { selection.setAll(ofTypes: Set(shownTypes), on: true) }
                .buttonStyle(.dgControl)
                .font(DGFont.footnote.weight(.semibold))
                .foregroundStyle(DGColor.coralText)
            Button("None") { selection.setAll(ofTypes: Set(shownTypes), on: false) }
                .buttonStyle(.dgControl)
                .font(DGFont.footnote.weight(.semibold))
                .foregroundStyle(DGColor.coralText)
        }
    }

    private func groupLabel(_ type: String) -> some View {
        Text(EquipmentOption(rawValue: type)?.title ?? type)
            .font(DGFont.condensedLabel(12))
            .foregroundStyle(DGColor.ink4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DGSpace.s5)
            .padding(.top, DGSpace.s3)
            .padding(.bottom, DGSpace.s1)
            .accessibilityAddTraits(.isHeader)
    }

    private func machineRow(_ machine: Machine) -> some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s3) {
            MachineThumbnailView(machine: machine)
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.displayName).font(DGFont.body).foregroundStyle(DGColor.ink1)
                Text(machine.aliases.prefix(2).joined(separator: " · "))
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(machine.displayName, isOn: binding(machine))
                .labelsHidden()
                .tint(DGColor.coral)
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func binding(_ machine: Machine) -> Binding<Bool> {
        Binding(get: { selection.isOn(machine) }, set: { selection.set(machine, on: $0) })
    }
}
