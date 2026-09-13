import SwiftUI

/// Freeform note editor, used for both a per-exercise note and (from
/// `ActiveWorkoutView`) the whole-session note. Glass sheet, 240 pt detent.
struct NotesSheet: View {
    var title: String
    var onSave: (String) -> Void

    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, text: String, onSave: @escaping (String) -> Void) {
        self.title = title
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
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .padding(DGSpace.s3)
                .background(
                    DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                )
            DGPrimaryButton(title: "Save note", symbol: "checkmark", height: 52) {
                onSave(text)
                dismiss()
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.hidden)
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NotesSheet(title: "Bench Press note", text: "Elbows tucked, pause at chest", onSave: { _ in })
        }
}
