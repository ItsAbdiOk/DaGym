import GymCore
import SwiftData
import SwiftUI
import UIKit

/// The Active Workout screen: glass nav header, stat strip, muscle map, PR
/// banner and the exercise list, with a sticky rest pill + action bar at the
/// bottom. Tab bar visibility is the parent's job. See mockups 02_00 / 02_01.
struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    var onFinish: (WorkoutSummary) -> Void

    @Environment(WorkoutStore.self) var store
    @Environment(Preferences.self) var preferences
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var activeSheet: ActiveSheet?
    @State var menuExerciseID: UUID?
    @State var showFinishConfirm = false
    @State var restAlertPlayer = RestAlertPlayer()
    /// Voice logging's controller, built once in `onAppear` rather than as a `@State` initial
    /// value: that expression re-runs every time this struct is initialised (every re-render of
    /// `RootView`'s cover closure), and the controller's recognizer owns an `SFSpeechRecognizer`
    /// and an `AVAudioEngine` whose `deinit` reaches into the shared audio session.
    @State var voiceController: VoiceLogController?
    /// What "Add routine…" offers, read once as the sheet is requested.
    @State var addRoutineChoices: [RoutineInfo] = []
    /// The active equipment profile for the plate chip, read once here and on store changes
    /// rather than by the chip from `body` (`PlateChip.inventory`).
    @State var inventory: ProgressionEquipment?
    @State var flashOpacity: Double = 0
    @State var chromeCollapse = ChromeCollapseState()
    @State var undoAction: UndoAction?
    /// The "…" menu's one-session layout choice; nil means the saved `Preferences.workoutLayout`.
    /// Deliberately not written back — the default only changes in Settings › Workout.
    @State var layoutOverride: WorkoutLayout?
    /// "Keep going" hides the all-done banner until another set is added and left open.
    @State var allDoneDismissed = false
    /// "SUNDAY · 13 SEP" — formatted once on appear (`Self.startedAtLabel(for:)`), since the
    /// header re-renders on every set edit and two `DateFormatter`s per render added up.
    @State var startedAtLabel = ""
    /// The pending write for the workout note: every keystroke used to `sync` (a walk of every
    /// exercise and set plus a SwiftData save) per character. Now one write, 500 ms after typing
    /// stops, and on the sheet-dismiss / finish paths that sync anyway.
    @State private var noteSyncTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if chromeCollapse.isCollapsed {
                condensedNavHeader
            } else {
                navHeader
                statStrip
            }
            ScrollView {
                VStack(spacing: DGSpace.s4) {
                    musclesCard
                    if let pr = session.prBanner { PRBanner(info: pr) }
                    if showsAllDone {
                        AllDoneBanner(
                            setsDone: session.setsDone, onFinish: finishSession,
                            onKeepGoing: { allDoneDismissed = true }
                        )
                    }
                    exerciseList
                    workoutNoteField
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s4)
                .padding(.bottom, 140)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                updateChrome(offset: newOffset)
            }
            .background(AmbientWash())
        }
        .background(DGColor.bgBase)
        .dgWarmHaptics()
        .overlay(alignment: .bottom) { bottomChrome }
        .dgUndoToast($undoAction)
        .overlay { Color.white.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false) }
        .restLiveActivity(session: session, onSessionMutation: { store.sync(session: session) })
        .task {
            startedAtLabel = Self.startedAtLabel(for: session)
            inventory = store.activeInventory()
            session.onRestTick = handleRestTick
            session.restHaptics = preferences.restHaptics
            session.restPauseSeconds = preferences.restPauseSeconds
            session.defaultRestSeconds = preferences.defaultRestSeconds
            restAlertPlayer.playsOnSilent = preferences.playRestSoundOnSilent
            await runTimers()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tickTimers() }
        }
        .onChange(of: store.changeToken) { _, _ in inventory = store.activeInventory() }
        .onChange(of: preferences.restHaptics) { _, enabled in session.restHaptics = enabled }
        .onChange(of: preferences.restPauseSeconds) { _, seconds in session.restPauseSeconds = seconds }
        .onChange(of: preferences.defaultRestSeconds) { _, seconds in
            session.defaultRestSeconds = seconds
        }
        .onChange(of: preferences.playRestSoundOnSilent) { _, on in restAlertPlayer.playsOnSilent = on }
        .onChange(of: session.hasUndoneSets) { _, hasUndone in
            if hasUndone { allDoneDismissed = false }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = preferences.keepScreenAwake
            if voiceController == nil {
                voiceController = VoiceLogController(
                    recognizer: OnDeviceSpeechRecognizer(), speaker: VoiceSpeechSynthesizer()
                )
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            cancelPendingNoteSync()
        }
        .sheet(item: $activeSheet, onDismiss: { store.sync(session: session) }, content: sheetContent)
        .confirmationDialog(finishPrompt, isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish workout", action: finishSession)
            Button("Discard workout", role: .destructive, action: discardSession)
        }
        .confirmationDialog("Exercise", isPresented: menuIsPresented, titleVisibility: .visible) {
            exerciseMenuButtons
        }
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
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .dgCard(padding: DGSpace.s4)
    }

    /// Free-text note for the whole session, synced once typing pauses (`noteSyncTask`).
    private var workoutNoteField: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Workout note").dgLabel()
            TextField("Optional note for this session", text: $session.notes, axis: .vertical)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1...4)
                .onChange(of: session.notes) { _, _ in scheduleNoteSync() }
                .onSubmit { syncNoteNow() }
        }
        .dgCard(padding: DGSpace.s4)
    }

    static let noteSyncDelay = Duration.milliseconds(500)

    private func scheduleNoteSync() {
        noteSyncTask?.cancel()
        noteSyncTask = Task {
            try? await Task.sleep(for: Self.noteSyncDelay)
            guard !Task.isCancelled else { return }
            store.sync(session: session)
        }
    }

    private func syncNoteNow() {
        noteSyncTask?.cancel()
        store.sync(session: session)
    }

    /// Finish and Discard call this first: a debounced note sync that fires *after* `finish`
    /// has pruned the unfinished rows would re-insert them into the finished workout.
    func cancelPendingNoteSync() {
        noteSyncTask?.cancel()
        noteSyncTask = nil
    }

    // MARK: Exercise list

    /// Keyed by the entries' ids, not their positions: `@State` inside a card (an open swipe
    /// row, a revealed incline column) follows the exercise when one above it is removed,
    /// reordered or supersetted, instead of migrating onto whatever now sits at that index.
    private var exerciseList: some View {
        ForEach(exerciseSlots) { group in
            if group.members.count > 1 {
                supersetGroup(group.members)
            } else if let slot = group.members.first {
                exerciseCard(at: slot.index)
            }
        }
    }

    /// `session.groupedIndices` with each chunk (and each member) keyed by its entry's id.
    private var exerciseSlots: [ExerciseSlotGroup] {
        session.groupedIndices.map { indices in
            ExerciseSlotGroup(members: indices.map { ExerciseSlot(id: session.exercises[$0].id, index: $0) })
        }
    }

    private struct ExerciseSlot: Identifiable {
        let id: UUID
        let index: Int
    }

    private struct ExerciseSlotGroup: Identifiable {
        let members: [ExerciseSlot]
        var id: UUID { members[0].id }
    }

    private func supersetGroup(_ members: [ExerciseSlot]) -> some View {
        let rounds = members.map { session.exercises[$0.index].sets.count }.min() ?? 0
        return VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Superset · \(rounds) rounds").dgLabel(DGColor.setSuperset)
            HStack(spacing: DGSpace.s3) {
                RoundedRectangle(cornerRadius: 2.5).fill(DGColor.setSuperset).frame(width: 5)
                VStack(spacing: DGSpace.s2) {
                    ForEach(members) { exerciseCard(at: $0.index) }
                }
            }
        }
    }

    /// A hold or a run gets its card wrapped in `HoldAwareCard`, which is what reads
    /// `session.timedHold` — so the hold's once-a-second tick re-renders that slot, not this
    /// whole screen.
    @ViewBuilder
    private func exerciseCard(at index: Int) -> some View {
        let entry = session.exercises[index]
        if entry.isTimed || entry.isCardio {
            HoldAwareCard(
                session: session, entry: entry, onPauseResume: { session.pauseResumeTimedHold() },
                onStop: stopTimedHold, card: { staticExerciseCard(entry: entry, index: index) }
            )
        } else {
            staticExerciseCard(entry: entry, index: index)
        }
    }

    private func staticExerciseCard(entry: WorkoutExerciseEntry, index: Int) -> some View {
        ExerciseCard(
            entry: entry, isOnDeck: session.onDeckIndex == index, effortScale: session.effortScale,
            layout: layout,
            onTapWeight: { setID in
                activeSheet = .keypad(exerciseID: entry.id, setID: setID, field: .weight)
            },
            onTapReps: { setID in
                activeSheet = .keypad(exerciseID: entry.id, setID: setID, field: .reps)
            },
            onTapEffort: { setID in activeSheet = .effort(exerciseID: entry.id, setID: setID) },
            onToggleDone: { set in toggleDone(exerciseID: entry.id, set: set) },
            onMore: { menuExerciseID = entry.id },
            onStartTimed: { setID in startTimedHold(exerciseID: entry.id, setID: setID) },
            onTapCardioField: { setID, field in
                activeSheet = .keypad(exerciseID: entry.id, setID: setID, field: field)
            },
            onNote: { activeSheet = .notes(exerciseID: entry.id) },
            onDeleteSet: { setID in deleteSet(exerciseID: entry.id, setID: setID) },
            onChangeSetKind: { setID, kind in
                changeSetKind(exerciseID: entry.id, setID: setID, to: kind)
            },
            onInsertSet: { setID, kind in insertSet(exerciseID: entry.id, after: setID, kind: kind) },
            onAdjustWeight: { setID, delta in
                adjustSet(exerciseID: entry.id, setID: setID, weightDelta: delta)
            },
            onAdjustReps: { setID, delta in
                adjustSet(exerciseID: entry.id, setID: setID, repsDelta: delta)
            },
            inventory: inventory
        )
    }

    // MARK: Bottom sticky group

    var bottomGroup: some View {
        VStack(spacing: DGSpace.s2) {
            RestPillSection(session: session)
            WorkoutActionBar(
                onAddExercise: { activeSheet = .addExercise }, onReorder: { activeSheet = .reorder }
            )
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s2)
    }

    // MARK: Timers

    /// Once-a-second refresh of the wall-clock-derived rest and hold timers. The sleep only paces
    /// re-rendering; the timers read `Date()`, so a suspended process lands on the right number
    /// the moment it wakes (see also the `scenePhase` tick above).
    func runTimers() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            tickTimers()
        }
    }

    func tickTimers() {
        session.tickRest()
        session.tickTimedHold()
    }
}

/// The sticky "Exercise / Reorder / Coach" pill under the rest timer.
private struct WorkoutActionBar: View {
    var onAddExercise: () -> Void
    var onReorder: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            actionItem(title: "Exercise", symbol: "plus", tint: DGColor.coralText, action: onAddExercise)
            actionItem(title: "Reorder", symbol: "list.bullet", tint: DGColor.ink2, action: onReorder)
            actionItem(title: "Coach", symbol: "sparkles", tint: DGColor.ink4, action: {})
                .opacity(0.5)
                .disabled(true)
                .accessibilityHint("Coming soon")
        }
        .frame(minHeight: 56)
        .dgGlass(.thick, in: Capsule())
        .dgDenseType()
    }

    private func actionItem(
        title: String, symbol: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text(title).font(DGFont.condensedLabel(13)).textCase(.uppercase)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dgControl)
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
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        ActiveWorkoutView(session: SampleData.makeSession(), onFinish: { _ in })
            .environment(WorkoutStore(context: container.mainContext))
            .environment(Preferences())
    }
}

extension ActiveWorkoutView {
    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// "SUNDAY · 13 SEP", or "BACKFILL · 11 SEP" for a session logged after the fact.
    static func startedAtLabel(for session: WorkoutSession) -> String {
        let dateText = dayMonthFormatter.string(from: session.startedAt).uppercased()
        guard session.isBackfilled else {
            let dayText = weekdayFormatter.string(from: session.startedAt).uppercased()
            return "\(dayText) · \(dateText)"
        }
        return "Backfill · \(dateText)".uppercased()
    }

    /// What the exercise list renders in: the session override when the "…" menu set one, else
    /// the saved preference.
    var layout: WorkoutLayout { layoutOverride ?? preferences.workoutLayout }

    var muscleNames: String {
        let names = session.musclesHit.sorted { $0.value > $1.value }.map(\.key.displayName)
        return names.isEmpty ? "Not started yet" : names.joined(separator: ", ")
    }

    /// The all-done banner: every planned set ticked, and "Keep going" not yet tapped.
    var showsAllDone: Bool {
        session.setsTotal > 0 && !session.hasUndoneSets && !allDoneDismissed
    }

    /// What finishing now would save — the title of the finish/discard dialog, so it never just
    /// repeats the button label.
    var finishPrompt: String {
        let done = session.setsDone
        guard done > 0 else { return "Nothing logged yet" }
        let elapsed = WorkoutSession.clock(session.elapsedSeconds())
        return "\(done) of \(session.setsTotal) sets done · \(elapsed)"
    }
}
