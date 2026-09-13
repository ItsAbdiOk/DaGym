import GymCore
import SwiftUI

/// Drag-to-reorder list of the workout's exercises, writing the new order
/// straight back onto the session.
struct ReorderExercisesSheet: View {
    @Bindable var session: WorkoutSession
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.exercises) { entry in
                    Text(entry.exercise.name.uppercased())
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                        .listRowBackground(DGColor.surface2)
                }
                .onMove { indices, newOffset in
                    session.exercises.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DGColor.bgBase)
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ReorderExercisesSheet(session: SampleData.makeSession(), onDone: {})
        }
}
