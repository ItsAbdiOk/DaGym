import SwiftUI

/// Drag-to-reorder list of the draft's exercises. A superset is one row and moves as a unit,
/// mirroring `ReorderExercisesSheet` for a live session.
struct ReorderDraftSheet: View {
    @Binding var items: [EditableExercise]
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(RoutineReorder.units(groups: items.map(\.supersetGroup)), id: \.self) { unit in
                    unitRow(unit)
                        .listRowBackground(DGColor.surface2)
                }
                .onMove { indices, newOffset in
                    items = RoutineReorder.moveUnits(
                        items, groups: items.map(\.supersetGroup), fromOffsets: indices, toOffset: newOffset
                    )
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
                Text(items[index].exercise.name.uppercased())
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
            }
        }
    }
}

/// Moves whole units of a routine draft — a superset group travels together — the way
/// `WorkoutSession.moveUnits` does for a live session, so the builder's drag reorder can't split
/// a pair.
enum RoutineReorder {
    /// Runs of adjacent items sharing a non-nil superset group, as index chunks in order.
    static func units(groups: [Int?]) -> [[Int]] {
        var result: [[Int]] = []
        var start = 0
        while start < groups.count {
            let group = groups[start]
            var chunk = [start]
            var next = start + 1
            if group != nil {
                while next < groups.count, groups[next] == group {
                    chunk.append(next)
                    next += 1
                }
            }
            result.append(chunk)
            start = next
        }
        return result
    }

    /// Applies a `List.onMove` offset pair — expressed over `units(groups:)` rows — to `items`.
    static func moveUnits<Item>(
        _ items: [Item], groups: [Int?], fromOffsets source: IndexSet, toOffset destination: Int
    ) -> [Item] {
        let units = units(groups: groups).map { $0.map { items[$0] } }
        let moving = source.compactMap { units.indices.contains($0) ? units[$0] : nil }
        var remaining = units.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = min(destination - source.filter { $0 < destination }.count, remaining.count)
        remaining.insert(contentsOf: moving, at: max(0, insertAt))
        return remaining.flatMap { $0 }
    }
}

/// Dashed-outline "add exercise" affordance.
struct AddExerciseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
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
        .buttonStyle(.dgCard)
    }
}
