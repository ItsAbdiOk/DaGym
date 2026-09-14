import GymCore
import SwiftUI

/// Drag-to-reorder list of the workout's exercises, writing the new order
/// straight back onto the session. A superset is one row and moves as a unit.
struct ReorderExercisesSheet: View {
    @Bindable var session: WorkoutSession
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.groupedIndices, id: \.self) { unit in
                    unitRow(unit)
                        .listRowBackground(DGColor.surface2)
                }
                .onMove { indices, newOffset in
                    session.moveUnits(fromOffsets: indices, toOffset: newOffset)
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

    private func unitRow(_ unit: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if unit.count > 1 { Text("Superset").dgLabel(DGColor.setSuperset) }
            ForEach(unit, id: \.self) { index in
                Text(session.exercises[index].exercise.name.uppercased())
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ReorderExercisesSheet(session: SampleData.makeSession(), onDone: {})
        }
}
