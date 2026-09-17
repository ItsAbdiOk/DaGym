import GymCore
import SwiftUI

/// Source badge, counts, unmatched exercises and problems for one parsed CSV, before the user
/// confirms the import.
struct ImportCSVPreviewSheet: View {
    var preview: ImportPreview
    var onConfirm: () -> Void
    var onCancel: () -> Void
    /// Called when the user picks a weight unit for a file that named none; nil hides the picker.
    var onPickUnit: ((WeightUnit) -> Void)?

    /// The picker's own selection. Routing the choice through `@State` + `onChange` rather than a
    /// `Binding(get:set:)` over `onPickUnit` keeps a non-`Sendable` closure out of `Binding`'s
    /// `@Sendable` setter — which Swift 6 rejects, and which the compiler crashes on if you make
    /// the closure type `@MainActor @Sendable` to satisfy it.
    @State private var pickedUnit = WeightUnit.kg
    @State private var requestedUnit: WeightUnit?

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            header
            // The unmatched-name and problem lists are unbounded (a Strong export can carry
            // dozens), so they scroll and the Cancel/Import row stays reachable underneath.
            ScrollView {
                VStack(spacing: DGSpace.s5) {
                    countsCard
                    if preview.weightUnitAssumed, let onPickUnit {
                        unitPicker(onPickUnit)
                    }
                    if !preview.matchedExercises.isEmpty {
                        namesCard(
                            title: "\(preview.matchedExercises.count) matched exercise"
                                + (preview.matchedExercises.count == 1 ? "" : "s"),
                            names: preview.matchedExercises.map { "\($0.sourceName) → \($0.libraryName)" }
                        )
                    }
                    if !preview.unmatchedExerciseNames.isEmpty {
                        namesCard(
                            title: "\(preview.unmatchedExerciseNames.count) new exercise"
                                + (preview.unmatchedExerciseNames.count == 1 ? "" : "s"),
                            names: preview.unmatchedExerciseNames
                        )
                    }
                    if !preview.problems.isEmpty {
                        namesCard(
                            title: "\(preview.problems.count) problem"
                                + (preview.problems.count == 1 ? "" : "s"),
                            names: preview.problems.map { "Line \($0.line): \($0.message)" }
                        )
                    }
                }
            }
            actions
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents(hasExtras ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.hidden)
    }

    private var hasExtras: Bool {
        !preview.unmatchedExerciseNames.isEmpty || !preview.problems.isEmpty
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Import from \(preview.source.displayName)")
                .font(DGFont.title2)
                .foregroundStyle(DGColor.ink1)
            Text("Nothing is imported until you confirm")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countsCard: some View {
        VStack(spacing: DGSpace.s2) {
            DGAdaptiveStack(spacing: 0, threshold: .accessibility3) {
                StatTile(value: "\(preview.newWorkoutCount)", label: "Workouts")
                StatTile(value: "\(preview.setsCount)", label: "Sets")
            }
            .dgCard(padding: 0)
            if preview.alreadyImportedCount > 0 {
                Text("\(preview.alreadyImportedCount) already in your history — they'll be skipped.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Shown only when the file's weight column named no unit. Assuming kg silently turns an
    /// American lifter's 225 lb bench into a 225 kg one, so the guess is made visible and
    /// changeable before anything is written.
    private func unitPicker(_ onPick: @escaping (WeightUnit) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Weight unit").dgLabel()
            Text("This file doesn't say what unit its weights are in. Reading them as:")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            Picker("Weight unit", selection: $pickedUnit) {
                Text("Kilograms").tag(WeightUnit.kg)
                Text("Pounds").tag(WeightUnit.lb)
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DGSpace.s4)
        .dgCard(padding: 0)
        .onAppear { pickedUnit = preview.weightUnit }
        // Only a real change re-parses; the `onAppear` seed above must not kick one off.
        // Compared against the last *requested* unit, not the preview's: while a re-parse is
        // in flight the preview still shows the old unit, and a quick LB→KG double tap would
        // otherwise skip the KG parse and leave the LB one to land. The `onAppear` seed above
        // equals the preview's unit, so it never kicks one off.
        .onChange(of: pickedUnit) { _, unit in
            guard unit != (requestedUnit ?? preview.weightUnit) else { return }
            requestedUnit = unit
            onPick(unit)
        }
    }

    private func namesCard(title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).dgLabel()
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                ForEach(names, id: \.self) { name in
                    Text(name).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DGSpace.s4)
            .dgCard(padding: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: DGSpace.s3) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(15))
                .foregroundStyle(DGColor.ink3)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .dgGlass(.regular, radius: DGRadius.lg)
            DGPrimaryButton(title: "Import", action: onConfirm)
        }
    }
}

#Preview {
    ImportCSVPreviewSheet(
        preview: ImportPreview(
            source: .strong, workouts: [], setsCount: 12, unmatchedExerciseNames: ["Cable Fly"],
            problems: []
        ),
        onConfirm: {}, onCancel: {}, onPickUnit: nil
    )
}
