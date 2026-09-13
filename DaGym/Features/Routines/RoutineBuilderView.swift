import GymCore
import SwiftUI

/// Routine Builder — "Edit Routine". Name, muscles hit, progression rule,
/// a superset pair with a violet rail, and a standalone exercise below.
struct RoutineBuilderView: View {
    var routine: RoutineInfo
    var onCancel: () -> Void
    var onSave: () -> Void

    @State private var name: String

    init(routine: RoutineInfo, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.routine = routine
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: routine.name)
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    navRow
                    NameCard(name: $name, routine: routine)
                    ProgressionCard(routine: routine)
                    SupersetGroup(exercises: pushALayout.superset)
                    if let solo = pushALayout.solo {
                        BuilderExerciseCard(data: solo)
                    }
                    AddExerciseButton()
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
    }

    private var navRow: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .dgLabel()
            Spacer()
            Text("Edit Routine")
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Button("Save", action: onSave)
                .buttonStyle(.plain)
                .dgLabel(DGColor.coralText)
        }
    }

    /// Arranges the routine's exercises to match the mockup: exercise 1 +
    /// the triceps exercise share superset A, the third exercise stands alone.
    private var pushALayout: (superset: [ExerciseCardData], solo: ExerciseCardData?) {
        let items = routine.exercises
        guard let first = items.first else { return ([], nil) }
        let ropeIndex = items.firstIndex { $0.name.lowercased().contains("rope") } ?? min(1, items.count - 1)
        let rope = items.indices.contains(ropeIndex) ? items[ropeIndex] : nil
        let soloIndex = items.indices.contains(2) ? 2 : nil
        let solo = soloIndex.map { items[$0] }
        var superset = [ExerciseCardData.forBench(first)]
        if let rope, rope.id != first.id { superset.append(.forTricepsRope(rope)) }
        let soloData = solo.map { ExerciseCardData.forOverhead($0) }
        return (superset, soloData)
    }
}

/// "NAME" card: editable title, hairline, body map, "HITS" summary.
private struct NameCard: View {
    @Binding var name: String
    var routine: RoutineInfo

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Name").dgLabel()
            TextField("Routine name", text: $name)
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
                .textFieldStyle(.plain)
            Divider().overlay(DGColor.hairline)
            HStack(alignment: .top, spacing: DGSpace.s4) {
                BodyMapPair(intensity: routine.hitMap, height: 44)
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text("Hits").dgLabel()
                    Text("Chest, front delts, triceps · light on back")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dgCard()
    }
}

/// Violet "progression rule" card, styled like WhyCard.
private struct ProgressionCard: View {
    var routine: RoutineInfo

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Progression Rule").dgLabel(DGColor.aiVioletText)
            Text(routine.progressionRule)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
            Text(routine.progressionDetail)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DGColor.aiViolet.opacity(0.12),
            in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.aiViolet.opacity(0.3), lineWidth: 1)
        }
    }
}

/// "SUPERSET · A" label with a 5 pt violet rail spanning the two cards.
private struct SupersetGroup: View {
    var exercises: [ExerciseCardData]

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Superset · A").dgLabel(DGColor.aiVioletText)
            HStack(alignment: .top, spacing: DGSpace.s3) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(DGColor.aiViolet)
                    .frame(width: 5)
                    .frame(maxHeight: .infinity)
                VStack(spacing: DGSpace.s3) {
                    ForEach(exercises) { BuilderExerciseCard(data: $0) }
                }
            }
        }
    }
}

/// One exercise row inside the builder: drag handle, name, tags, footnote.
private struct BuilderExerciseCard: View {
    var data: ExerciseCardData

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
                Text(data.name)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
            }
            HStack(spacing: DGSpace.s2) {
                ForEach(data.tags) { tag in
                    DGTag(text: tag.text, tint: tag.tint, wash: tag.wash)
                }
            }
            if let footnote = data.footnote {
                Text(footnote)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }
}

/// Dashed-outline "add exercise" affordance.
private struct AddExerciseButton: View {
    var body: some View {
        Button {
        } label: {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add Exercise")
                    .font(DGFont.condensedLabel(14))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(DGColor.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .dgGlass(.thin, radius: DGRadius.lg)
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                    .strokeBorder(DGColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(DGPressStyle())
    }
}

/// Display data for one exercise card in the builder.
private struct ExerciseCardData: Identifiable {
    struct Tag: Identifiable {
        let id = UUID()
        let text: String
        let tint: Color
        let wash: Color
    }

    let id: UUID
    let name: String
    let tags: [Tag]
    let footnote: String?

    static func forBench(_ exercise: ExerciseInfo) -> ExerciseCardData {
        ExerciseCardData(
            id: exercise.id, name: exercise.name,
            tags: [
                Tag(text: "2 warm-up", tint: DGColor.setWarmup, wash: DGColor.setWarmup.opacity(0.16)),
                Tag(text: "3 × 6–8", tint: DGColor.ink2, wash: DGColor.surface3),
                Tag(text: "RPE 8", tint: DGColor.rpeHard, wash: DGColor.surface3)
            ],
            footnote: "Target 82.5 kg · rest 2:30"
        )
    }

    static func forTricepsRope(_ exercise: ExerciseInfo) -> ExerciseCardData {
        ExerciseCardData(
            id: exercise.id, name: exercise.name,
            tags: [
                Tag(text: "3 × 12", tint: DGColor.ink2, wash: DGColor.surface3),
                Tag(text: "Drop on last", tint: DGColor.infoText, wash: DGColor.info.opacity(0.16))
            ],
            footnote: nil
        )
    }

    static func forOverhead(_ exercise: ExerciseInfo) -> ExerciseCardData {
        ExerciseCardData(
            id: exercise.id, name: exercise.name,
            tags: [
                Tag(text: "4 × 6", tint: DGColor.ink2, wash: DGColor.surface3),
                Tag(text: "75% of 1RM", tint: DGColor.coralText, wash: DGColor.coralWash)
            ],
            footnote: nil
        )
    }
}

#Preview {
    RoutineBuilderView(routine: SampleData.pushA, onCancel: {}, onSave: {})
}
