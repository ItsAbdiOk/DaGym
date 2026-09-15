import GymCore
import SwiftUI

/// One exercise's page of the active workout (screens 2A–2G): the name in the top safe band,
/// the set position with its progress dots, the layout for the current set's shape, and the
/// one capsule. Logging swaps the middle block for the inline rest (3A) in place, so the next
/// set arrives where the last one was.
///
/// `session.exercises` is a value array on an `@Observable`, so every crown detent on any
/// page replaces it and re-evaluates every mounted page. What the page derives from the set's
/// *identity* — its shape, position and dot counts — is kept in `layout` and only rebuilt when
/// the on-deck set changes; a detent only re-reads the numbers.
struct ExercisePage: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences
    var entry: WorkoutExerciseEntry
    /// This page's position in the pager, from the `ForEach` — searching the session for it
    /// on every render was one more walk per detent per page.
    var pageIndex: Int

    @State private var focus: CrownField?
    @State private var crown: Double = 0
    @State private var showEffortPicker = false
    @State private var showVoice = false
    @State private var layout: SetLayout?

    private var session: WorkoutSession? { store.session }
    private var currentSet: SetEntry? { entry.sets.first { !$0.isDone } }
    private var isCurrentPage: Bool { store.pageIndex == pageIndex }

    /// What the page derives from which set is on deck, not from its values.
    struct SetLayout: Equatable {
        var setID: UUID
        var shape: SetShape
        var position: (index: Int, count: Int)
        var dotsDone: Int
        var dotsTotal: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.setID == rhs.setID && lhs.shape == rhs.shape && lhs.position == rhs.position
                && lhs.dotsDone == rhs.dotsDone && lhs.dotsTotal == rhs.dotsTotal
        }

        init(entry: WorkoutExerciseEntry, set: SetEntry) {
            setID = set.id
            shape = SetShape.shape(for: entry, set: set)
            position = SetFormat.position(of: set, in: entry)
            dotsDone = entry.sets.filter { $0.isDone && $0.kind.countsTowardStats }.count
            dotsTotal = entry.sets.filter { $0.kind.countsTowardStats }.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sits under the status-bar clock row (the pager ignores the top safe area so every
            // page lays out the same), narrower than the band's 150 pt cap.
            SafeBandText(
                text: entry.exercise.name, font: WatchFont.title, color: WatchColor.ink, maxWidth: 120
            )
            .padding(.top, WatchMetric.pageTop)
            if let set = currentSet {
                setBody(set, layout: layout(for: set))
            } else {
                completedBody
            }
        }
        .padding(.horizontal, WatchMetric.gutter)
        .modifier(
            ExerciseCrownModifier(entry: entry, currentSetID: currentSet?.id, focus: $focus, crown: $crown)
        )
        .onChange(of: currentSet?.id, initial: true) { _, _ in
            layout = currentSet.map { SetLayout(entry: entry, set: $0) }
        }
        .sheet(isPresented: $showEffortPicker) { EffortPickerSheet(entry: entry) }
        .sheet(isPresented: $showVoice) { VoiceLogView() }
        .onAppear {
            if store.debugShowVoice, isCurrentPage {
                store.debugShowVoice = false
                showVoice = true
            }
        }
    }

    /// The cached layout when it is for `set`; built on the spot for the first render, before
    /// `onChange(initial:)` has stored one.
    private func layout(for set: SetEntry) -> SetLayout {
        if let layout, layout.setID == set.id { return layout }
        return SetLayout(entry: entry, set: set)
    }

    @ViewBuilder private func setBody(_ set: SetEntry, layout: SetLayout) -> some View {
        let resting = session.map { $0.isResting && $0.restTotal <= InlineRestView.maxInlineSeconds } ?? false
        let showsInlineRest = resting && isCurrentPage
        // The header and steppers are one VoiceOver container, so the row reads as one element
        // ("Set 2 of 4, 100 kilograms by 5 reps") before its children.
        VStack(spacing: 0) {
            SetHeader(
                shape: layout.shape, set: set, position: layout.position,
                dotsDone: layout.dotsDone, dotsTotal: layout.dotsTotal,
                amrapTarget: store.amrapTargets[set.id]
            )
            if showsInlineRest {
                InlineRestView(entry: entry)
            } else {
                SetShapeView(
                    entry: entry, set: set, shape: layout.shape, focus: $focus, unit: preferences.weightUnit,
                    onFocus: give(focus:), onAdjust: adjust(field:direction:), onEffortTap: effortTap
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(setRowLabel(shape: layout.shape, set: set, position: layout.position))
        if !showsInlineRest {
            Spacer(minLength: 4)
            footer(shape: layout.shape, set: set)
        }
    }

    private func setRowLabel(shape: SetShape, set: SetEntry, position: (index: Int, count: Int)) -> String {
        WatchAccessibility.setRow(
            shape: shape, position: position, weightKg: set.weightKg, reps: set.reps,
            targetSeconds: set.cardioSeconds, unit: preferences.weightUnit
        )
    }

    private var completedBody: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(WatchColor.commit)
            Text("All \(entry.sets.count) sets logged")
                .font(WatchFont.body)
                .foregroundStyle(WatchColor.inkSecondary)
            Spacer()
            CapsuleButton(title: "Add set", tint: WatchColor.card) {
                session?.addSet(exerciseID: entry.id, kind: .working)
            }
            .foregroundStyle(WatchColor.ink)
        }
    }

    // MARK: - Footer

    @ViewBuilder private func footer(shape: SetShape, set: SetEntry) -> some View {
        HStack(spacing: 8) {
            switch shape {
            case .warmup:
                CapsuleButton(title: "Log warm-up", style: .hollow) { log() }
            case .perSide:
                let left = store.hasLoggedLeft(exerciseID: entry.id)
                CapsuleButton(title: left ? "Log right" : "Log left") { logSide(isLeft: !left, set: set) }
            case .timedHold, .cardio:
                let running = session?.timedHold?.setID == set.id
                CapsuleButton(
                    title: running ? "Stop & log" : "Start",
                    tint: running ? WatchColor.commit : WatchColor.accent
                ) {
                    if running {
                        store.stopHold(exerciseID: entry.id)
                    } else {
                        store.startHold(exerciseID: entry.id)
                    }
                }
            case .standard, .amrap, .bodyweight, .assisted:
                CapsuleButton(title: "Log set") { log() }
            }
            if preferences.voiceLog, shape != .timedHold, shape != .cardio {
                MicButton { showVoice = true }
            }
        }
        .padding(.bottom, 2)
    }

    private func log() {
        store.logCurrentSet(exerciseID: entry.id)
        focus = nil
    }

    private func logSide(isLeft: Bool, set: SetEntry) {
        let perSide = max(0, set.reps / 2)
        if isLeft {
            store.logLeftSide(exerciseID: entry.id, reps: perSide)
        } else {
            store.logRightSide(exerciseID: entry.id, reps: perSide)
            focus = nil
        }
    }

    private var effortIsTapThrough: Bool { WatchMetric.isSmall }

    private func effortTap() {
        if effortIsTapThrough { showEffortPicker = true } else { give(focus: .effort) }
    }

    // MARK: - Crown

    private func give(focus field: CrownField) {
        guard let set = currentSet else { return }
        focus = field
        crown = ExerciseCrown.value(for: field, set: set, entry: entry, preferences: preferences)
        Haptics.step()
    }

    /// VoiceOver's swipe up / down on a stepper: one crown detent either way, clamped to the
    /// crown's own range, without moving crown focus.
    private func adjust(field: CrownField, direction: AccessibilityAdjustmentDirection) {
        guard let set = currentSet else { return }
        let current = ExerciseCrown.value(for: field, set: set, entry: entry, preferences: preferences)
        let next = ExerciseCrown.adjusted(
            current, field: field, direction: direction, exercise: entry.exercise,
            unit: preferences.weightUnit
        )
        ExerciseCrown.write(field: field, value: next, entry: entry, preferences: preferences, store: store)
        if focus == field { crown = next }
        Haptics.step()
    }
}

/// The 50 pt indigo mic circle beside the capsule.
struct MicButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WatchColor.voice)
                .frame(width: WatchMetric.capsule - 6, height: WatchMetric.capsule)
                .background(Circle().fill(WatchColor.card).frame(width: WatchMetric.capsule - 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log by voice")
    }
}
