import GymCore
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

/// One planned cardio set: a kind tag, a target time stepper (minutes) and a target distance
/// stepper in the lifter's unit. No reps, no weight — a run's plan is how far and how long.
struct BuilderCardioSetRow: View {
    @Binding var set: PlannedSetDraft

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            HStack(spacing: DGSpace.s3) {
                kindMenu
                Stepper(value: minutesBinding, in: 0...300, step: 1) {
                    Text(timeLabel).font(DGFont.body).foregroundStyle(DGColor.ink1)
                }
            }
            Stepper(value: distanceBinding, in: 0...200, step: 0.25) {
                Text(distanceLabel).font(DGFont.body).foregroundStyle(DGColor.ink1)
            }
            .accessibilityLabel("Target distance")
        }
    }

    private var kindMenu: some View {
        Menu {
            ForEach(SetKind.allCases, id: \.self) { kind in
                Button(kind.displayName) { set.kind = kind }
            }
        } label: {
            DGTag(text: set.kind.displayName, tint: DGColor.ink2, wash: set.kind.color.opacity(0.22))
        }
    }

    private var timeLabel: String {
        guard let seconds = set.targetSeconds, seconds > 0 else { return "No time target" }
        return "\(CardioPace.clock(seconds)) target"
    }

    private var distanceLabel: String {
        guard let meters = set.targetDistanceMeters, meters > 0 else { return "No distance target" }
        return "\(preferences.formatDistance(meters: meters)) target"
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { (set.targetSeconds ?? 0) / 60 },
            set: { set.targetSeconds = $0 > 0 ? $0 * 60 : nil }
        )
    }

    /// Steps in the display unit; storage stays metres.
    private var distanceBinding: Binding<Double> {
        Binding(
            get: { preferences.distanceUnit.display(meters: set.targetDistanceMeters ?? 0) },
            set: { set.targetDistanceMeters = $0 > 0 ? preferences.distanceUnit.toMeters($0) : nil }
        )
    }
}
