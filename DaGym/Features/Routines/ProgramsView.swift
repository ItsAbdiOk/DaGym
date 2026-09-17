import GymCore
import SwiftData
import SwiftUI

/// Multi-week programs (plan.md §6.5): a list of programs with start/stop and a week strip
/// showing normal/deload/rest weeks. Reached from `RoutinesTabView` via a "Programs" button.
struct ProgramsView: View {
    var onDone: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var programs: [ProgramInfo] = []
    @State private var showingNew = false
    @State private var showingGenerator = false
    @State private var undoAction: UndoAction?

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
        .refreshOnStoreChange(refresh)
        .dgUndoToast($undoAction)
        .confirmationDialog("New Program", isPresented: $showingNew, titleVisibility: .visible) {
            Button("Build one for me") { showingGenerator = true }
            ForEach(StarterProgramKind.allCases) { kind in
                Button(kind.rawValue) { create(kind) }
            }
        }
        .sheet(isPresented: $showingGenerator) {
            ProgramGeneratorSheet { application in
                undoAction = UndoAction(message: "Created \(application.name)") {
                    store.undoProgramApplication(application)
                    refresh()
                }
                refresh()
            }
        }
    }

    private var navRow: some View {
        HStack {
            Button("Done", action: onDone)
                .buttonStyle(.dgControl)
                .dgLabel()
            Spacer()
            Text("Programs")
                .font(DGFont.title2)
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
                    ShareRoutineButton(title: program.name) { includeWeights in
                        PlanShareService.exportProgram(
                            id: program.id, context: store.context, includeWeights: includeWeights
                        )
                    }
                    .padding(DGSpace.s3)
                }
            }
        }
    }

    /// `preferences.trainingCalendar` carries `weekStartsMonday`, so the week a program says
    /// you're in is the same week the Progress tab and the widget draw.
    private func refresh() { programs = store.programs(calendar: preferences.trainingCalendar) }

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
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                if program.isActive { Text("Active").dgLabel(DGColor.coralText) }
            }
            Text(statusLine)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
            weekStrip
            actions
        }
        .dgCard()
    }

    /// Which week the lifter is actually in — the one thing a multi-week program is for, and
    /// the one thing this card never showed.
    private var statusLine: String {
        guard let week = program.currentWeek else {
            if program.isFinished { return "Finished · \(program.weeks)-week block" }
            return program.startedAt == nil ? "Not started · \(program.weeks) weeks" : "Not running"
        }
        let kind = program.currentWeekKind.map { " · \($0.displayName)" } ?? ""
        let cycle = (program.currentCycle ?? 1) > 1 ? " · round \(program.currentCycle ?? 1)" : ""
        return "Week \(week) of \(program.weeks)\(kind)\(cycle)"
    }

    private var weekStrip: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(program.programWeeks) { week in
                VStack(spacing: 2) {
                    Text("W\(week.index)")
                        .font(DGFont.caption)
                        .foregroundStyle(week.index == program.currentWeek ? DGColor.ink1 : DGColor.ink3)
                    // Shape carries the kind as well as colour: a ring for a deload, a hollow
                    // dot for rest, a filled dot for a normal week.
                    weekDot(week.kind)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(DGColor.ink1, lineWidth: week.index == program.currentWeek ? 2 : 0)
                                .padding(-3)
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusLine)
    }

    @ViewBuilder
    private func weekDot(_ kind: ProgramWeekKind) -> some View {
        switch kind {
        case .normal: Circle().fill(color(kind))
        case .deload: Circle().strokeBorder(color(kind), lineWidth: 3)
        case .rest: Circle().strokeBorder(DGColor.ink4, lineWidth: 1)
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
                    .buttonStyle(.dgControl)
                    .dgLabel(DGColor.danger)
                Button("Complete", action: onComplete)
                    .buttonStyle(.dgControl)
                    .dgLabel()
            } else {
                Button("Start", action: onStart)
                    .buttonStyle(.dgControl)
                    .dgLabel(DGColor.coralText)
            }
        }
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        ProgramsView(onDone: {})
            .environment(WorkoutStore(context: container.mainContext))
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
