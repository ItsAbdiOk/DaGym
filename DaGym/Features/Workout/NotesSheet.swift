import SwiftUI

/// Freeform note editor, used for both a per-exercise note and (from
/// `ActiveWorkoutView`) the whole-session note. Glass sheet, 240 pt detent.
///
/// Pass `exerciseID` to get the "This session / Next time / Always" scope chips
/// (features.md adopt 5): a session note goes back through `onSave` as before, while the other
/// two are stored as `ExerciseNoteModel` rows — `WorkoutStore.pinnedNote(exerciseID:workoutID:)`
/// hands the card the one to show. Without an `exerciseID` the sheet is the plain editor.
struct NotesSheet: View {
    var title: String
    var exerciseID: UUID?
    var workoutID: UUID?
    var onSave: (String) -> Void

    @State private var text: String
    @State private var scope = ExerciseNoteScope.session
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(
        title: String, text: String, exerciseID: UUID? = nil, workoutID: UUID? = nil,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.exerciseID = exerciseID
        self.workoutID = workoutID
        self.onSave = onSave
        self._text = State(initialValue: text)
    }

    var body: some View {
        VStack(spacing: DGSpace.s4) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            Text(title)
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if exerciseID != nil { scopeRow }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .padding(DGSpace.s3)
                .background(
                    DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                )
            DGPrimaryButton(title: "Save note", symbol: "checkmark", height: 52, action: saveNote)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(exerciseID == nil ? 240 : 300)])
        .presentationDragIndicator(.hidden)
    }

    private var scopeRow: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(ExerciseNoteScope.allCases) { option in
                DGChip(title: option.title, selected: option == scope) { scope = option }
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note scope")
    }

    private func saveNote() {
        if let exerciseID, scope != .session {
            store.addExerciseNote(exerciseID: exerciseID, text: text, scope: scope, workoutID: workoutID)
        } else {
            onSave(text)
        }
        dismiss()
    }
}

#Preview {
    if let store = PreviewStore.make() {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                NotesSheet(
                    title: "Bench Press note", text: "Elbows tucked, pause at chest",
                    exerciseID: SampleData.bench.id, onSave: { _ in }
                )
            }
            .environment(store)
    }
}
