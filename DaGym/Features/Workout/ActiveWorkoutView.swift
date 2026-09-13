import GymCore
import SwiftData
import SwiftUI

/// The Active Workout screen: glass nav header, stat strip, muscle map, PR
/// banner and the exercise list, with a sticky rest pill + action bar at the
/// bottom. Tab bar visibility is the parent's job. See mockups 02_00 / 02_01.
struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    var onFinish: (WorkoutSummary) -> Void

    @Environment(WorkoutStore.self) var store
    @Environment(\.dismiss) var dismiss
    @State var activeSheet: ActiveSheet?
    @State var menuExerciseID: UUID?
    @State var showFinishConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            navHeader
            statStrip
            ScrollView {
                VStack(spacing: DGSpace.s4) {
                    musclesCard
                    if let pr = session.prBanner { PRBanner(info: pr) }
                    exerciseList
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s4)
                .padding(.bottom, 140)
            }
            .background(AmbientWash())
        }
        .background(DGColor.bgBase)
        .overlay(alignment: .bottom) { bottomGroup }
        .task { await runTimers() }
        .sheet(item: $activeSheet) { sheet in sheetContent(sheet) }
        .confirmationDialog("Finish workout", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish workout", action: finishSession)
            Button("Discard workout", role: .destructive, action: discardSession)
        }
        .confirmationDialog("Exercise", isPresented: menuIsPresented, titleVisibility: .visible) {
            exerciseMenuButtons
        }
    }

    // MARK: Header

    private var navHeader: some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(startedAtLabel).dgLabel()
                Text(session.title)
                    .font(DGFont.title1)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer(minLength: DGSpace.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Elapsed").dgLabel()
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(WorkoutSession.clock(session.elapsedSeconds(at: context.date)))
                        .dgMetric(DGFont.metricL)
                        .foregroundStyle(DGColor.ink1)
                }
            }
            DGPrimaryButton(title: "Finish", height: 44) { showFinishConfirm = true }
                .frame(width: 96)
                .accessibilityIdentifier(A11yID.workoutFinish)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.top, DGSpace.s2)
        .padding(.bottom, DGSpace.s3)
        .dgGlass(.regular, radius: 0)
    }

    /// "SUNDAY · 13 SEP", or "BACKFILL · 11 SEP" for a session logged after the fact.
    private var startedAtLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let dateText = formatter.string(from: session.startedAt).uppercased()
        guard session.isBackfilled else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            let dayText = dayFormatter.string(from: session.startedAt).uppercased()
            return "\(dayText) · \(dateText)"
        }
        return "Backfill · \(dateText)".uppercased()
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            StatTile(value: WorkoutSession.format(session.volumeKg), label: "kg volume")
            Divider().overlay(DGColor.hairline)
            StatTile(value: "\(session.setsDone) / \(session.setsTotal)", label: "sets")
            Divider().overlay(DGColor.hairline)
            StatTile(value: "\(session.prCount)", label: "pr", tint: DGColor.prGoldText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s3)
    }

    // MARK: Muscles + PR

    private var musclesCard: some View {
        HStack(spacing: DGSpace.s3) {
            BodyMapPair(intensity: session.musclesHit, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Muscles hit today").dgLabel()
                Text(muscleNames)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer(minLength: 0)
        }
        .dgCard(padding: DGSpace.s4)
    }

    private var muscleNames: String {
        let names = session.musclesHit.sorted { $0.value > $1.value }.map(\.key.displayName)
        return names.isEmpty ? "Not started yet" : names.joined(separator: ", ")
    }

    // MARK: Exercise list

    private var exerciseList: some View {
        ForEach(groupedIndices, id: \.self) { group in
            if group.count > 1 {
                supersetGroup(indices: group)
            } else if let index = group.first {
                exerciseCard(at: index)
            }
        }
    }

    /// Consecutive runs of exercises sharing a non-nil supersetGroup id.
    private var groupedIndices: [[Int]] {
        var result: [[Int]] = []
        var start = 0
        let exercises = session.exercises
        while start < exercises.count {
            let group = exercises[start].supersetGroup
            var chunk = [start]
            var next = start + 1
            if group != nil {
                while next < exercises.count, exercises[next].supersetGroup == group {
                    chunk.append(next)
                    next += 1
                }
            }
            result.append(chunk)
            start = next
        }
        return result
    }

    private func supersetGroup(indices: [Int]) -> some View {
        let rounds = indices.map { session.exercises[$0].sets.count }.min() ?? 0
        return VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Superset · \(rounds) rounds").dgLabel(DGColor.setSuperset)
            HStack(spacing: DGSpace.s3) {
                RoundedRectangle(cornerRadius: 2.5).fill(DGColor.setSuperset).frame(width: 5)
                VStack(spacing: DGSpace.s2) {
                    ForEach(indices, id: \.self) { exerciseCard(at: $0) }
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseCard(at index: Int) -> some View {
        let entry = session.exercises[index]
        if entry.isTimed, let hold = session.timedHold, hold.exerciseID == entry.id {
            TimedHoldCard(
                exerciseName: entry.exercise.name, hold: hold,
                onPauseResume: { session.pauseResumeTimedHold() }, onStop: stopTimedHold
            )
        } else {
            ExerciseCard(
                entry: entry, isOnDeck: session.onDeckIndex == index, effortScale: session.effortScale,
                onTapWeight: { setID in
                    activeSheet = .keypad(exerciseID: entry.id, setID: setID, field: .weight)
                },
                onTapReps: { setID in
                    activeSheet = .keypad(exerciseID: entry.id, setID: setID, field: .reps)
                },
                onTapEffort: { setID in activeSheet = .effort(exerciseID: entry.id, setID: setID) },
                onToggleDone: { set in toggleDone(exerciseID: entry.id, set: set) },
                onMore: { menuExerciseID = entry.id },
                onStartTimed: { setID in startTimedHold(exerciseID: entry.id, setID: setID) }
            )
        }
    }

    // MARK: Bottom sticky group

    private var bottomGroup: some View {
        VStack(spacing: DGSpace.s2) {
            if session.isResting {
                RestPill(
                    remaining: session.restRemaining, total: session.restTotal,
                    nextLabel: session.restNextLabel,
                    onAddThirty: { session.adjustRest(by: 30) }, onSkip: { session.skipRest() }
                )
            }
            actionBar
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s2)
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionItem(title: "Exercise", symbol: "plus", tint: DGColor.coralText) {
                activeSheet = .addExercise
            }
            actionItem(title: "Reorder", symbol: "list.bullet", tint: DGColor.ink2) {
                activeSheet = .reorder
            }
            actionItem(title: "Coach", symbol: "sparkles", tint: DGColor.ink4, action: {})
                .opacity(0.5)
        }
        .frame(height: 56)
        .dgGlass(.thick, in: Capsule())
    }

    private func actionItem(
        title: String, symbol: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                Text(title).font(DGFont.condensedLabel(13)).textCase(.uppercase)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Timers

    func runTimers() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            session.tickRest()
            session.tickTimedHold()
        }
    }
}

/// Sweeps gold once when a set beats a personal record.
private struct PRBanner: View {
    var info: PersonalRecordInfo

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: "star.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DGColor.prGoldDeep)
                .frame(width: 44, height: 44)
                .background(
                    DGColor.prGold, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("New PR — \(info.exerciseName)").dgLabel(DGColor.prGoldText)
                Text(info.line)
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dgCard(
            radius: DGRadius.md, fill: DGColor.prGold.opacity(0.14),
            stroke: DGColor.prGold.opacity(0.4), padding: DGSpace.s4
        )
    }
}

/// Identifies the one sheet presented over the workout at a time.
enum ActiveSheet: Identifiable {
    case keypad(exerciseID: UUID, setID: UUID, field: KeypadField)
    case effort(exerciseID: UUID, setID: UUID)
    case swap(exercise: ExerciseInfo)
    case addExercise
    case reorder

    enum KeypadField: String { case weight, reps }

    var id: String {
        switch self {
        case .keypad(let exerciseID, let setID, let field):
            "keypad-\(exerciseID)-\(setID)-\(field.rawValue)"
        case .effort(let exerciseID, let setID):
            "effort-\(exerciseID)-\(setID)"
        case .swap(let exercise):
            "swap-\(exercise.id)"
        case .addExercise:
            "add-exercise"
        case .reorder:
            "reorder"
        }
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        ActiveWorkoutView(session: SampleData.makeSession(), onFinish: { _ in })
            .environment(WorkoutStore(context: container.mainContext))
    }
}
