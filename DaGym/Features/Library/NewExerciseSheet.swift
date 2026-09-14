import GymCore
import SwiftData
import SwiftUI

/// New Exercise sheet — the minimum viable custom exercise: a name and a
/// primary muscle. Everything else can be filled in later. Saves straight
/// to the store.
struct NewExerciseSheet: View {
    var onSave: (ExerciseInfo) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscle: Muscle?
    @State private var equipment: EquipmentOption = .other
    @State private var loggingStyle: ExerciseInfo.LoggingStyle = .weightReps
    @State private var isPerSide = false
    @State private var barType: BarChoice = .olympic

    var body: some View {
        ZStack {
            AmbientWash()
            VStack(alignment: .leading, spacing: DGSpace.s5) {
                navRow
                formCard
                Text("Only name and muscle are required. Everything else can wait until you've used it once.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                Spacer()
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s3)
        }
    }

    private var navRow: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink3)
            Spacer()
            Text("New Exercise")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(canSave ? DGColor.coralText : DGColor.ink4)
                .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && muscle != nil
    }

    private var showsBarRow: Bool {
        equipment == .barbell || equipment == .ezBar
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            NameRow(name: $name)
            Divider().overlay(DGColor.hairline)
            MuscleRow(muscle: $muscle)
            Divider().overlay(DGColor.hairline)
            EquipmentRow(equipment: $equipment)
            Divider().overlay(DGColor.hairline)
            LoggingStyleRow(loggingStyle: $loggingStyle)
            Divider().overlay(DGColor.hairline)
            PerSideRow(isPerSide: $isPerSide)
            if showsBarRow {
                Divider().overlay(DGColor.hairline)
                BarTypeRow(equipment: equipment, barType: $barType)
            }
        }
        .dgCard(padding: 0)
    }

    private func save() {
        guard let muscle, canSave else { return }
        let created = store.createCustomExercise(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), primary: [muscle],
            equipment: equipment.rawValue, style: loggingStyle, isPerSide: isPerSide,
            barType: showsBarRow ? barType.storeValue(for: equipment) : nil
        )
        onSave(created)
        dismiss()
    }
}

/// Bar choice for the New Exercise sheet's conditional bar-type row.
enum BarChoice: String, CaseIterable, Identifiable {
    case olympic, womens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .olympic: "Olympic"
        case .womens: "Women's"
        }
    }

    /// EZ bar equipment always stores "ezBar" regardless of the picked choice.
    func storeValue(for equipment: EquipmentOption) -> String {
        equipment == .ezBar ? "ezBar" : rawValue
    }
}

/// Shared row chrome: a 90 pt micro label and trailing content.
private struct FormRow<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(label).dgLabel().frame(width: 90, alignment: .leading)
            content
        }
        .padding(.vertical, DGSpace.s3)
        .padding(.horizontal, DGSpace.s5)
    }
}

private struct NameRow: View {
    @Binding var name: String

    var body: some View {
        FormRow(label: "Name *") {
            TextField("Exercise name", text: $name)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
        }
    }
}

private struct MuscleRow: View {
    @Binding var muscle: Muscle?

    var body: some View {
        FormRow(label: "Muscle *") {
            Menu {
                ForEach(Muscle.allCases) { option in
                    Button(option.displayName) { muscle = option }
                }
            } label: {
                Text(muscle?.displayName ?? "Select")
                    .font(DGFont.body)
                    .foregroundStyle(muscle == nil ? DGColor.ink4 : DGColor.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.dgRow)
        }
    }
}

private struct EquipmentRow: View {
    @Binding var equipment: EquipmentOption

    var body: some View {
        FormRow(label: "Equipment") {
            Menu {
                ForEach(EquipmentOption.allCases) { option in
                    Button(option.title) { equipment = option }
                }
            } label: {
                Text(equipment.title)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.dgRow)
        }
    }
}

private struct LoggingStyleRow: View {
    @Binding var loggingStyle: ExerciseInfo.LoggingStyle

    var body: some View {
        FormRow(label: "Log As") {
            Menu {
                ForEach(ExerciseInfo.LoggingStyle.allCases, id: \.self) { style in
                    Button(style.rawValue) { loggingStyle = style }
                }
            } label: {
                Text(loggingStyle.rawValue)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.dgRow)
        }
    }
}

private struct PerSideRow: View {
    @Binding var isPerSide: Bool

    var body: some View {
        FormRow(label: "Per Side") {
            Toggle("", isOn: $isPerSide)
                .labelsHidden()
                .tint(DGColor.coral)
        }
    }
}

private struct BarTypeRow: View {
    var equipment: EquipmentOption
    @Binding var barType: BarChoice

    var body: some View {
        FormRow(label: "Bar Type") {
            if equipment == .ezBar {
                Text("EZ Bar")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Menu {
                    ForEach(BarChoice.allCases) { choice in
                        Button(choice.title) { barType = choice }
                    }
                } label: {
                    Text(barType.title)
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.dgRow)
            }
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NewExerciseSheet { _ in }
            .environment(store)
    }
}
