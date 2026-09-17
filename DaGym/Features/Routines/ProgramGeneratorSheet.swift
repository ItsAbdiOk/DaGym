import GymCore
import SwiftUI

/// "Build me a program" (plan.md §6.6): a short questionnaire → `ProgramTemplateEngine`'s
/// deterministic skeleton → the coach model (or the template's default picks) fills each slot
/// from a candidate pool → `ProgramDraftValidator` → preview → Apply creates the routines and
/// the program through the store, with Undo. The model only ever chooses exercises and a name;
/// the split, sets, reps and progression rule are the engine's.
struct ProgramGeneratorSheet: View {
    var onApplied: (GeneratedProgramApplication) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(CoachServices.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @State private var goal = TrainingGoal.hypertrophy
    @State private var daysPerWeek = 4
    @State private var sessionMinutes = 60
    @State private var experience = ExperienceLevel.intermediate
    @State private var excludedEquipment: Set<String> = []
    @State private var excludedMuscles: Set<Muscle> = []
    @State private var preview: Preview?
    @State private var isBuilding = false
    @State private var problem: String?

    struct Preview {
        var template: ProgramTemplate
        var request: ProgramRequest
        var draft: ProgramDraft
        var names: [UUID: String]
        var fromModel: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        if let preview {
                            previewSection(preview)
                        } else {
                            questionnaire
                        }
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s10)
                }
            }
            .navigationTitle(preview == nil ? "Build a Program" : "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationBackground(DGColor.surface1)
    }

    // MARK: - Questionnaire

    private var questionnaire: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            picker("Goal", selection: $goal, options: TrainingGoal.allCases, title: \.displayName)
            stepper("Days a week", value: $daysPerWeek, range: ProgramRequest.daysRange, step: 1) {
                "\($0)"
            }
            stepper(
                "Session length", value: $sessionMinutes,
                range: ProgramRequest.sessionMinutesRange, step: 15
            ) {
                "\($0) min"
            }
            picker("Experience", selection: $experience, options: ExperienceLevel.allCases,
                   title: \.displayName)
            chips("Leave out equipment", options: EquipmentOption.allCases.map { ($0.rawValue, $0.title) }) {
                toggleBinding($excludedEquipment, $0)
            }
            chips("Leave out muscles", options: Muscle.allCases.map { ($0, $0.displayName) }) {
                toggleBinding($excludedMuscles, $0)
            }
            if let problem {
                Text(problem).font(DGFont.footnote).foregroundStyle(DGColor.danger)
            }
            DGPrimaryButton(title: isBuilding ? "Building…" : "Build it", symbol: "sparkles") {
                Task { await build() }
            }
            .disabled(isBuilding)
            .accessibilityIdentifier(A11yID.programBuild)
            Text(
                "The split, sets, reps and progression come from fixed templates. "
                    + (coach.isUsingLanguageModel
                        ? "Apple's on-device model picks the exercises from your library "
                            + "and names it — nothing leaves your iPhone."
                        : "The exercises are the template's default picks from your library.")
            )
            .font(DGFont.footnote)
            .foregroundStyle(DGColor.ink4)
        }
    }

    private func picker<Option: Hashable>(
        _ label: String, selection: Binding<Option>, options: [Option], title: KeyPath<Option, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(label).dgLabel()
            HStack(spacing: DGSpace.s2) {
                ForEach(options, id: \.self) { option in
                    DGChip(
                        title: option[keyPath: title], selected: selection.wrappedValue == option,
                        selectedFill: DGColor.coral, selectedInk: DGColor.inkOnCoral
                    ) { selection.wrappedValue = option }
                }
            }
        }
    }

    private func stepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        format: @escaping (Int) -> String
    ) -> some View {
        SettingsRow(label: label) {
            Stepper(value: value, in: range, step: step) {
                Text(format(value.wrappedValue)).font(DGFont.subhead).foregroundStyle(DGColor.ink3)
            }
            .accessibilityLabel(label)
            .accessibilityValue(format(value.wrappedValue))
        }
        .dgCard(padding: 0)
    }

    private func chips<Option: Hashable>(
        _ label: String, options: [(Option, String)], binding: @escaping (Option) -> Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(label).dgLabel()
            let columns = [GridItem(.adaptive(minimum: 100), spacing: DGSpace.s2)]
            LazyVGrid(
                columns: columns, alignment: .leading, spacing: DGSpace.s2
            ) {
                ForEach(options, id: \.0) { option, title in
                    let isOn = binding(option)
                    DGChip(
                        title: title, selected: isOn.wrappedValue, selectedFill: DGColor.surface3,
                        selectedInk: DGColor.ink1
                    ) { isOn.wrappedValue.toggle() }
                }
            }
        }
    }

    private func toggleBinding<Option: Hashable>(
        _ set: Binding<Set<Option>>, _ option: Option
    ) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(option) },
            set: { if $0 { set.wrappedValue.insert(option) } else { set.wrappedValue.remove(option) } }
        )
    }

    // MARK: - Preview

    private func previewSection(_ preview: Preview) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            Text(preview.draft.name)
                .font(DGFont.title1)
                .foregroundStyle(DGColor.ink1)
            Text("\(preview.template.splitName) · \(preview.template.weeks) weeks, last week deload · "
                + preview.template.rule.displayName)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            ForEach(preview.template.days) { day in
                VStack(alignment: .leading, spacing: DGSpace.s2) {
                    Text(day.name).dgLabel()
                    ForEach(day.slots) { slot in
                        HStack {
                            Text(preview.names[preview.draft.exerciseID(for: slot.id) ?? UUID()] ?? "—")
                                .font(DGFont.body)
                                .foregroundStyle(DGColor.ink1)
                            Spacer()
                            Text("\(slot.sets) × \(slot.repLow)–\(slot.repHigh)")
                                .font(DGFont.subhead)
                                .foregroundStyle(DGColor.ink3)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .dgCard()
            }
            Text(preview.fromModel
                 ? "Exercises chosen by the on-device model, checked against your equipment and the template."
                 : "The template's default exercises from your library.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
            DGPrimaryButton(title: "Apply", symbol: "checkmark") { apply(preview) }
                .accessibilityIdentifier(A11yID.programApply)
            Button("Back to the questions") { self.preview = nil }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .foregroundStyle(DGColor.ink3)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func build() async {
        isBuilding = true
        defer { isBuilding = false }
        problem = nil
        let request = ProgramRequest(
            goal: goal, daysPerWeek: daysPerWeek, sessionMinutes: sessionMinutes, experience: experience,
            availableEquipment: store.equipmentKindsForProgram(), excludedEquipment: excludedEquipment,
            excludedMuscles: excludedMuscles, equipmentAvailability: store.equipmentAvailabilityForProgram()
        )
        let template = ProgramTemplateEngine.template(for: request)
        let pool = store.programPool(for: template, request: request)
        var fromModel = false
        var draft: ProgramDraft?
        if coach.isUsingLanguageModel, let modelDraft = try? await coach.model.draftProgram(
            template: template, pool: pool, request: request
        ) {
            draft = modelDraft
            fromModel = true
        } else {
            draft = ProgramDefaultPicks.draft(template: template, pool: pool, request: request)
        }
        guard let draft else {
            problem = "Your library doesn't have an exercise for every slot with this equipment. "
                + "Allow more equipment or leave out fewer muscles."
            return
        }
        let names = Dictionary(
            pool.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        preview = Preview(
            template: template, request: request, draft: draft,
            names: names, fromModel: fromModel
        )
    }

    private func apply(_ preview: Preview) {
        guard let application = store.applyProgramDraft(
            preview.draft, template: preview.template, request: preview.request
        ) else {
            problem = "Couldn't save the program — an exercise is no longer in your library."
            self.preview = nil
            return
        }
        onApplied(application)
        dismiss()
    }
}
