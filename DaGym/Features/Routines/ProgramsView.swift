import GymCore
import SwiftData
import SwiftUI

/// The Programs segment of the Train tab (plan.md §6.5): the active program as a card with its
/// week bar and Stop / Share, any other programs as a row group, the four starters under
/// "Start a new one", and the "Let the coach build a program" card that opens
/// `ProgramGeneratorSheet`.
struct ProgramsView: View {
    /// The active card's routine names open the builder on that routine (Train's own path).
    var onOpenRoutine: (UUID) -> Void = { _ in }

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var programs: [ProgramInfo] = []
    @State private var routineNames: [UUID: String] = [:]
    @State private var showingGenerator = false
    @State private var startingKind: StarterProgramKind?
    @State private var stopping: ProgramInfo?
    @State private var undoAction: UndoAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let active = programs.first(where: \.isActive) {
                ActiveProgramCard(
                    program: active, routines: active.routineIDs.compactMap { id in
                        routineNames[id].map { (id: id, name: $0) }
                    },
                    onStop: { stopping = active }, onShare: share(active), onOpenRoutine: onOpenRoutine
                )
            }
            if !others.isEmpty {
                kicker("Your programs")
                TrainRowGroup {
                    ForEach(Array(others.enumerated()), id: \.element.id) { offset, program in
                        ProgramRow(
                            program: program, isLast: offset == others.count - 1,
                            onStart: { start(program) }, onShare: share(program)
                        )
                    }
                }
            }
            kicker("Start a new one")
            TrainRowGroup {
                ForEach(Array(StarterProgramKind.allCases.enumerated()), id: \.element) { offset, kind in
                    StarterRow(kind: kind, isLast: offset == StarterProgramKind.allCases.count - 1) {
                        startingKind = kind
                    }
                }
            }
            coachCard.padding(.top, 12)
        }
        .task { refresh() }
        .refreshOnStoreChange(refresh)
        .dgUndoToast($undoAction)
        .confirmationDialog(
            startingKind?.rawValue ?? "", isPresented: Binding(
                get: { startingKind != nil }, set: { if !$0 { startingKind = nil } }
            ), titleVisibility: .visible, presenting: startingKind
        ) { kind in
            Button("Start program") { adopt(kind) }
        } message: { kind in
            Text(startMessage(for: kind))
        }
        .confirmationDialog(
            "Stop \(stopping?.name ?? "program")?", isPresented: Binding(
                get: { stopping != nil }, set: { if !$0 { stopping = nil } }
            ), titleVisibility: .visible, presenting: stopping
        ) { program in
            Button("Stop for now") { stop(program) }
            Button("Mark as complete") { complete(program) }
        } message: { _ in
            Text("Stopped programs stay in your list to start again. Completed ones are filed as finished.")
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

    private func kicker(_ text: String) -> some View {
        Text(text).dgLabel()
            .padding(.horizontal, DGSpace.s1)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    /// Everything that isn't the active program — stopped, not-yet-started and finished ones.
    private var others: [ProgramInfo] { programs.filter { !$0.isActive } }

    private var coachCard: some View {
        Button { showingGenerator = true } label: {
            HStack(spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let the coach build a program")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                    Text("Goal, days per week, equipment")
                        .font(.system(size: 13.5))
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                TrainChevron()
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.vertical, 14)
            .background(DGColor.coral.opacity(0.12), in: coachShape)
            .contentShape(coachShape)
        }
        .buttonStyle(.dgCard)
        .accessibilityIdentifier(A11yID.trainCoachProgram)
    }

    private var coachShape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    private func startMessage(for kind: StarterProgramKind) -> String {
        var text = "\(kind.summary). Its routines are added to Routines and the program starts today."
        if programs.contains(where: \.isActive) { text += " Your current program stops." }
        return text
    }

    private func share(_ program: ProgramInfo) -> (Bool) -> PlanDocument? {
        { includeWeights in
            PlanShareService.exportProgram(
                id: program.id, context: store.context, includeWeights: includeWeights
            )
        }
    }

    /// `preferences.trainingCalendar` carries `weekStartsMonday`, so the week a program says
    /// you're in is the same week the Progress tab and the widget draw.
    private func refresh() {
        programs = store.programs(calendar: preferences.trainingCalendar)
        routineNames = Dictionary(
            store.routines().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
    }

    /// The one-tap starter path Home and the Routines empty state use (`adoptStarterPlan`):
    /// creates — or reuses — the kind's program and starts it.
    private func adopt(_ kind: StarterProgramKind) {
        store.adoptStarterPlan(kind)
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

/// The active program: an "ACTIVE" pill and "Week 3 of 8 · Deload · round 1", the name, a
/// one-segment-per-week bar and Stop / Share.
private struct ActiveProgramCard: View {
    var program: ProgramInfo
    /// The program's routines in order, each a door to its builder.
    var routines: [(id: UUID, name: String)] = []
    var onStop: () -> Void
    var onShare: (Bool) -> PlanDocument?
    var onOpenRoutine: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DGSpace.s2) {
                Text("ACTIVE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.55)
                    .foregroundStyle(DGColor.inkOnCoral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DGColor.coral, in: Capsule())
                Text(program.statusLine)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
            }
            Text(program.name)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .padding(.top, 12)
            if !routines.isEmpty {
                routineChips.padding(.top, 10)
            }
            ProgramWeekBar(program: program)
                .padding(.top, 14)
            HStack(spacing: DGSpace.s2) {
                TrainQuietButton(title: "Stop", action: onStop)
                ShareRoutineButton(title: program.name, makeDocument: onShare, pillTitle: "Share")
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: DGRadius.lg, padding: DGSpace.s4)
    }

    /// "Push A › Pull A › Legs A" as quiet chips: the routines the program runs, each opening
    /// its builder, so the program is not a name you can only Stop or Share.
    private var routineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(routines, id: \.id) { routine in
                    Button { onOpenRoutine(routine.id) } label: {
                        HStack(spacing: 3) {
                            Text(routine.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DGColor.ink2)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(DGColor.ink4)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(DGColor.ink1.opacity(0.055), in: Capsule())
                    }
                    .buttonStyle(.dgControl)
                    .accessibilityHint("Opens the routine")
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// One segment per week: accent for the current week, a lighter accent for weeks done, grey
/// for weeks ahead. A deload or rest week ahead is outlined rather than filled so the plan's
/// shape still reads before you reach it.
private struct ProgramWeekBar: View {
    var program: ProgramInfo

    var body: some View {
        HStack(spacing: 5) {
            ForEach(program.programWeeks) { week in
                Capsule()
                    .fill(fill(for: week))
                    .overlay {
                        if week.kind != .normal, week.index > (program.currentWeek ?? 0) {
                            Capsule().strokeBorder(DGColor.ink1.opacity(0.18), lineWidth: 1)
                        }
                    }
                    .frame(height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weeksLabel)
    }

    private func fill(for week: ProgramWeekInfo) -> Color {
        let current = program.currentWeek ?? 0
        if week.index == current { return DGColor.coral }
        if week.index < current { return DGColor.coral.opacity(0.4) }
        return DGColor.ink1.opacity(0.08)
    }

    private var weeksLabel: String {
        let kinds = program.programWeeks.map { "week \($0.index) \($0.kind.displayName.lowercased())" }
        return "\(program.statusLine). " + kinds.joined(separator: ", ")
    }
}

/// A stopped, unstarted or finished program in the "Your programs" group: name over its status,
/// and an accent "Start" on the right; long-press to share.
private struct ProgramRow: View {
    var program: ProgramInfo
    var isLast: Bool
    var onStart: () -> Void
    var onShare: (Bool) -> PlanDocument?

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(program.name)
                    .font(.system(size: 15.5))
                    .foregroundStyle(DGColor.ink1)
                Text(program.statusLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DGColor.ink3)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button(program.isFinished ? "Run again" : "Start", action: onStart)
                .buttonStyle(.dgControl)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DGColor.coralText)
                .accessibilityLabel("Start \(program.name)")
            ShareRoutineButton(title: program.name, makeDocument: onShare)
        }
        .padding(.leading, 15)
        .padding(.trailing, DGSpace.s1)
        .frame(minHeight: 46)
        .trainRowDivider(isLast: isLast)
    }
}

/// One starter kind: "Push/Pull/Legs" over "3 days · 4-week cycle with a deload", a chevron.
private struct StarterRow: View {
    var kind: StarterProgramKind
    var isLast: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.rawValue)
                        .font(.system(size: 15.5))
                        .foregroundStyle(DGColor.ink1)
                    Text(kind.summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                TrainChevron()
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
            .trainRowDivider(isLast: isLast)
        }
        .buttonStyle(.dgRow)
        .accessibilityLabel("\(kind.rawValue), \(kind.summary)")
        .accessibilityIdentifier(A11yID.starterPlan(kind.rawValue))
    }
}

extension ProgramInfo {
    /// Which week the lifter is actually in — the one thing a multi-week program is for.
    var statusLine: String {
        guard let week = currentWeek else {
            if isFinished { return "Finished · \(weeks)-week block" }
            return startedAt == nil ? "Not started · \(weeks) weeks" : "Stopped · \(weeks) weeks"
        }
        let kind = currentWeekKind.map { " · \($0.displayName)" } ?? ""
        let cycle = (currentCycle ?? 1) > 1 ? " · round \(currentCycle ?? 1)" : ""
        return "Week \(week) of \(weeks)\(kind)\(cycle)"
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        ScrollView {
            ProgramsView().padding()
        }
        .environment(WorkoutStore(context: container.mainContext))
        .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
