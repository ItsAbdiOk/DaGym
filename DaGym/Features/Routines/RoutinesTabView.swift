import GymCore
import SwiftData
import SwiftUI

/// Routines tab — a card per saved routine with a "start" pill, a "+" to
/// create a new one, and tap-to-edit navigation into the builder.
struct RoutinesTabView: View {
    var onStart: (RoutineInfo) -> Void

    @Environment(WorkoutStore.self) private var store
    @State private var routines: [RoutineInfo] = []
    @State private var activeProfile: EquipmentProfileInfo?
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
                    .padding(.bottom, DGSpace.s6)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Destination.self) { destination in
                // Each destination draws its own Cancel/Done row, so the system bar (and its
                // back button) would only double up.
                Group {
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
                .toolbar(.hidden, for: .navigationBar)
            }
            .task { refresh() }
            .onChange(of: store.changeToken) { refresh() }
        }
        .dgWarmHaptics()
    }

    private var header: some View {
        HStack {
            Text("Routines")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            programsButton
            DGIconButton(symbol: "calendar", accessibilityLabel: "Schedule") {
                path.append(Destination.schedule)
            }
            DGIconButton(symbol: "plus", accessibilityLabel: "New routine") {
                path.append(Destination.new)
            }
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
        .buttonStyle(.dgControl)
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
                ZStack(alignment: .topTrailing) {
                    Button { path.append(Destination.edit(routine.id)) } label: {
                        RoutineCard(
                            routine: routine, missingEquipment: missingEquipment(for: routine),
                            profileName: activeProfile?.name ?? "", onStart: { onStart(routine) }
                        )
                    }
                    .buttonStyle(.dgCard)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { duplicate(routine) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(routine) }
                    }
                    ShareRoutineButton(title: routine.name) {
                        PlanShareService.exportRoutine(id: routine.id, context: store.context)
                    }
                    .padding(DGSpace.s3)
                }
            }
        }
    }

    private func refresh() {
        routines = store.routines()
        activeProfile = store.activeProfile()
    }

    /// Equipment the routine needs that the active profile lacks; empty when there's no profile
    /// or it lists everything, so a fresh install never shows a badge.
    private func missingEquipment(for routine: RoutineInfo) -> [String] {
        guard let activeProfile, activeProfile.restrictsLibrary else { return [] }
        return routine.equipmentOutside(Set(activeProfile.availableEquipment))
    }

    private func duplicate(_ routine: RoutineInfo) {
        store.duplicateRoutine(id: routine.id)
        refresh()
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

/// One routine card: glyph, name, estimate, exercise line, top muscle tags, an equipment
/// badge when the active profile can't cover it, and a coral "start" pill.
private struct RoutineCard: View {
    var routine: RoutineInfo
    var missingEquipment: [String] = []
    var profileName = ""
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(alignment: .center, spacing: DGSpace.s3) {
                RoutineGlyph(symbolName: routine.symbolName, tint: routine.tint, size: 32)
                Text(routine.name)
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                // Leaves room for the share button `RoutinesTabView` overlays in the top-right.
                Text("~\(routine.estimatedMinutes) MIN").dgLabel()
                    .padding(.trailing, DGTap.min - DGSpace.s3)
            }
            .accessibilityElement(children: .combine)
            Text(exerciseNames)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .lineLimit(2)
            if !missingEquipment.isEmpty {
                equipmentBadge
            }
            HStack(spacing: DGSpace.s2) {
                ForEach(topMuscles) { muscle in
                    DGTag(text: muscle.displayName)
                }
                Spacer(minLength: DGSpace.s2)
                startPill
                    .accessibilityLabel("Start \(routine.name)")
            }
        }
        .dgCard()
    }

    private var startPill: some View {
        Button("Start", action: onStart)
            .buttonStyle(.dgControl)
            .font(DGFont.condensedLabel(13))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(DGColor.inkOnCoral)
            .padding(.horizontal, DGSpace.s4)
            .frame(height: 36)
            .background(DGColor.coral, in: Capsule())
    }

    private var equipmentBadge: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text("Needs \(missingNames) — not in \(profileName)")
                .font(DGFont.footnote)
                .lineLimit(1)
        }
        .foregroundStyle(DGColor.warning)
        .accessibilityLabel("Needs \(missingNames), not in the \(profileName) profile")
    }

    private var missingNames: String {
        missingEquipment
            .map { EquipmentOption(rawValue: $0)?.title.lowercased() ?? $0 }
            .joined(separator: ", ")
    }

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
