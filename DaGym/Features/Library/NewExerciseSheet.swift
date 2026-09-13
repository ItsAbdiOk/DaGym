import GymCore
import SwiftUI

/// New Exercise sheet — the minimum viable custom exercise: a name and a
/// primary muscle. Everything else can be filled in later.
struct NewExerciseSheet: View {
    var onSave: (ExerciseInfo) -> Void

    @State private var name = ""
    @State private var muscle: Muscle?
    @State private var equipment = ""
    @State private var loggingStyle: ExerciseInfo.LoggingStyle = .weightReps
    @Environment(\.dismiss) private var dismiss

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
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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

    private var formCard: some View {
        VStack(spacing: 0) {
            NameRow(name: $name)
            Divider().overlay(DGColor.hairline)
            MuscleRow(muscle: $muscle)
            Divider().overlay(DGColor.hairline)
            EquipmentRow(equipment: $equipment)
            Divider().overlay(DGColor.hairline)
            LoggingStyleRow(loggingStyle: $loggingStyle)
        }
        .dgCard(padding: 0)
    }

    private func save() {
        guard let muscle, canSave else { return }
        let exercise = ExerciseInfo(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            primary: [muscle],
            equipment: equipment.trimmingCharacters(in: .whitespacesAndNewlines),
            isCustom: true,
            loggingStyle: loggingStyle
        )
        onSave(exercise)
        dismiss()
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
            .buttonStyle(.plain)
        }
    }
}

private struct EquipmentRow: View {
    @Binding var equipment: String

    var body: some View {
        FormRow(label: "Equipment") {
            TextField("Optional", text: $equipment)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
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
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NewExerciseSheet { _ in }
}
