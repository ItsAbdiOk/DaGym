import GymCore
import SwiftData
import SwiftUI

/// Multi-week programs (plan.md §6.5): a list of programs with start/stop and a week strip
/// showing normal/deload/rest weeks. Reached from `RoutinesTabView` via a "Programs" button.
struct ProgramsView: View {
    var onDone: () -> Void

    @Environment(WorkoutStore.self) private var store
    @State private var programs: [ProgramInfo] = []
    @State private var showingNew = false

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s5) {
                    navRow
                    list
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .task { refresh() }
        .onChange(of: store.changeToken) { refresh() }
        .confirmationDialog("New Program", isPresented: $showingNew, titleVisibility: .visible) {
            ForEach(StarterProgramKind.allCases) { kind in
                Button(kind.rawValue) { create(kind) }
            }
        }
    }

    private var navRow: some View {
        HStack {
            Button("Done", action: onDone)
                .buttonStyle(.plain)
                .dgLabel()
            Spacer()
            Text("Programs")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "plus", accessibilityLabel: "New program") { showingNew = true }
        }
    }

    @ViewBuilder
    private var list: some View {
        if programs.isEmpty {
            EmptyState(
                symbol: "calendar.badge.clock", title: "No Programs Yet",
                message: "Start a multi-week program to cycle routines automatically with a planned deload.",
                action: "New Program", onAction: { showingNew = true }
            )
        } else {
            ForEach(programs) { program in
                ZStack(alignment: .topTrailing) {
                    ProgramCard(
                        program: program, onStart: { start(program) }, onStop: { stop(program) },
                        onComplete: { complete(program) }
                    )
                    ShareRoutineButton(title: program.name) {
                        PlanShareService.exportProgram(id: program.id, context: store.context)
                    }
                    .padding(DGSpace.s3)
                }
            }
        }
    }

    private func refresh() { programs = store.programs() }

    private func create(_ kind: StarterProgramKind) {
        store.createProgram(from: kind)
        refresh()
    }

    private func start(_ program: ProgramInfo) {
        store.startProgram(id: program.id)
        refresh()
    }

    private func stop(_ program: ProgramInfo) {
        store.stopProgram(id: program.id)
        refresh()
    }

    private func complete(_ program: ProgramInfo) {
        store.completeProgram(id: program.id)
        refresh()
    }
}

/// One program: name, week strip, and start/stop/complete controls.
private struct ProgramCard: View {
    var program: ProgramInfo
    var onStart: () -> Void
    var onStop: () -> Void
    var onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(program.name)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                if program.isActive { Text("Active").dgLabel(DGColor.coralText) }
            }
            weekStrip
            actions
        }
        .dgCard()
    }

    private var weekStrip: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(program.programWeeks) { week in
                VStack(spacing: 2) {
                    Text("W\(week.index)").font(DGFont.caption).foregroundStyle(DGColor.ink3)
                    Circle().fill(color(week.kind)).frame(width: 10, height: 10)
                }
            }
        }
    }

    private func color(_ kind: ProgramWeekKind) -> Color {
        switch kind {
        case .normal: DGColor.coral
        case .deload: DGColor.aiViolet
        case .rest: DGColor.surface3
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: DGSpace.s3) {
            if program.isActive {
                Button("Stop", role: .destructive, action: onStop)
                    .buttonStyle(.plain)
                    .dgLabel(DGColor.danger)
                Button("Complete", action: onComplete)
                    .buttonStyle(.plain)
                    .dgLabel()
            } else {
                Button("Start", action: onStart)
                    .buttonStyle(.plain)
                    .dgLabel(DGColor.coralText)
            }
        }
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        ProgramsView(onDone: {})
            .environment(WorkoutStore(context: container.mainContext))
    } else {
        Text("Preview unavailable")
    }
}
