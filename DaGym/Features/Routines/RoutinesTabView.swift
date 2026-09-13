import GymCore
import SwiftData
import SwiftUI

/// Routines tab — a card per saved routine with a "start" pill, a "+" to
/// create a new one, and tap-to-edit navigation into the builder.
struct RoutinesTabView: View {
    var onStart: (RoutineInfo) -> Void

    @Environment(WorkoutStore.self) private var store
    @State private var routines: [RoutineInfo] = []
    @State private var path = NavigationPath()

    private enum Destination: Hashable {
        case edit(UUID)
        case new
        case schedule
        case programs
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: DGSpace.s5) {
                        header
                        list
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .edit(let id):
                    RoutineBuilderView(routineID: id, onDone: pop)
                case .new:
                    RoutineBuilderView(routineID: nil, onDone: pop)
                case .schedule:
                    ScheduleView(onDone: pop)
                case .programs:
                    ProgramsView(onDone: pop)
                }
            }
            .task { refresh() }
        }
    }

    private var header: some View {
        HStack {
            Text("Routines")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            programsButton
            DGIconButton(symbol: "calendar") { path.append(Destination.schedule) }
            DGIconButton(symbol: "plus") { path.append(Destination.new) }
        }
    }

    private var programsButton: some View {
        Button { path.append(Destination.programs) } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 13, weight: .semibold))
                Text("Programs").font(DGFont.condensedLabel(13)).tracking(1.2).textCase(.uppercase)
            }
            .foregroundStyle(DGColor.ink1)
            .padding(.horizontal, DGSpace.s3)
            .frame(height: 36)
            .dgGlass(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var list: some View {
        if routines.isEmpty {
            EmptyState(
                symbol: "dumbbell", title: "No Routines Yet",
                message: "Build a routine to see it here and schedule it for your training days.",
                action: "New Routine", onAction: { path.append(Destination.new) }
            )
        } else {
            ForEach(routines) { routine in
                Button { path.append(Destination.edit(routine.id)) } label: {
                    RoutineCard(routine: routine, onStart: { onStart(routine) })
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) { delete(routine) }
                }
            }
        }
    }

    private func refresh() {
        routines = store.routines()
    }

    private func pop() {
        if !path.isEmpty { path.removeLast() }
        refresh()
    }

    private func delete(_ routine: RoutineInfo) {
        store.deleteRoutine(id: routine.id)
        refresh()
    }
}

/// One routine card: name, estimate, exercise line, top muscle tags and a
/// coral "start" pill.
private struct RoutineCard: View {
    var routine: RoutineInfo
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(routine.name)
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Text("~\(estimatedMinutes) MIN").dgLabel()
            }
            Text(exerciseNames)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .lineLimit(2)
            HStack(spacing: DGSpace.s2) {
                ForEach(topMuscles) { muscle in
                    DGTag(text: muscle.displayName)
                }
                Spacer(minLength: DGSpace.s2)
                startPill
            }
        }
        .dgCard()
    }

    private var startPill: some View {
        Button("Start", action: onStart)
            .buttonStyle(.plain)
            .font(DGFont.condensedLabel(13))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(DGColor.inkOnCoral)
            .padding(.horizontal, DGSpace.s4)
            .frame(height: 36)
            .background(DGColor.coral, in: Capsule())
    }

    /// setCount × 2.5 min + 5, rounded down to the minute.
    private var estimatedMinutes: Int { Int(Double(routine.setCount) * 2.5) + 5 }
    private var exerciseNames: String { routine.exercises.map(\.name).joined(separator: " · ") }
    private var topMuscles: [Muscle] {
        routine.hitMap.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        RoutinesTabView(onStart: { _ in })
            .environment(WorkoutStore(context: container.mainContext))
    } else {
        Text("Preview unavailable")
    }
}
