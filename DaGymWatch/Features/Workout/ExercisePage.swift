import GymCore
import SwiftUI

/// One exercise's page of the active workout (screens 2A–2G): the name in the top safe band,
/// the set position with its progress dots, the layout for the current set's shape, and the
/// one capsule. Logging swaps the middle block for the inline rest (3A) in place, so the next
/// set arrives where the last one was.
struct ExercisePage: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences
    var entry: WorkoutExerciseEntry

    @State private var focus: CrownField?
    @State private var crown: Double = 0
    @State private var showEffortPicker = false
    @State private var showVoice = false

    private var session: WorkoutSession? { store.session }
    private var currentSet: SetEntry? { entry.sets.first { !$0.isDone } }

    var body: some View {
        VStack(spacing: 0) {
            // Sits under the status-bar clock row (the pager ignores the top safe area so every
            // page lays out the same), narrower than the band's 150 pt cap.
            SafeBandText(
                text: entry.exercise.name, font: WatchFont.title, color: WatchColor.ink, maxWidth: 120
            )
            .padding(.top, WatchMetric.pageTop)
            if let set = currentSet {
                setBody(set)
            } else {
                completedBody
            }
        }
        .padding(.horizontal, WatchMetric.gutter)
        .modifier(CrownBinding(crown: $crown, focus: focus, step: crownStep, range: crownRange))
        .onChange(of: crown) { _, value in applyCrown(value) }
        .onChange(of: currentSet?.id) { _, _ in focus = nil }
        .sheet(isPresented: $showEffortPicker) { EffortPickerSheet(entry: entry) }
        .sheet(isPresented: $showVoice) { VoiceLogView() }
        .onAppear {
            if store.debugShowVoice, store.pageIndex == pageIndex {
                store.debugShowVoice = false
                showVoice = true
            }
        }
    }

    @ViewBuilder private func setBody(_ set: SetEntry) -> some View {
        let shape = SetShape.shape(for: entry, set: set)
        let position = SetFormat.position(of: set, in: entry)
        let resting = session.map { $0.isResting && $0.restTotal <= InlineRestView.maxInlineSeconds } ?? false
        // The header and steppers are one VoiceOver container, so the row reads as one element
        // ("Set 2 of 4, 100 kilograms by 5 reps") before its children.
        VStack(spacing: 0) {
            SetHeader(
                shape: shape, set: set, position: position,
                dotsDone: entry.sets.filter { $0.isDone && $0.kind.countsTowardStats }.count,
                dotsTotal: entry.sets.filter { $0.kind.countsTowardStats }.count,
                amrapTarget: store.amrapTargets[set.id]
            )
            if resting, store.pageIndex == pageIndex {
                InlineRestView(entry: entry)
            } else {
                SetShapeView(
                    entry: entry, set: set, shape: shape, focus: $focus, unit: preferences.weightUnit,
                    onFocus: give(focus:), onAdjust: adjust(field:direction:), onEffortTap: effortTap
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(setRowLabel(shape: shape, set: set, position: position))
        if !(resting && store.pageIndex == pageIndex) {
            Spacer(minLength: 4)
            footer(shape: shape, set: set)
        }
    }

    private func setRowLabel(shape: SetShape, set: SetEntry, position: (index: Int, count: Int)) -> String {
        WatchAccessibility.setRow(
            shape: shape, position: position, weightKg: set.weightKg, reps: set.reps,
            targetSeconds: set.cardioSeconds, unit: preferences.weightUnit
        )
    }

    private var pageIndex: Int { session?.exercises.firstIndex { $0.id == entry.id } ?? -1 }

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
        crown = crownValue(for: field, set: set)
        Haptics.step()
    }

    private func crownValue(for field: CrownField, set: SetEntry) -> Double {
        let unit = preferences.weightUnit
        switch field {
        case .weight: return unit.display(kg: set.weightKg)
        case .reps: return Double(entry.exercise.isPerSide ? set.reps / 2 : set.reps)
        case .effort: return set.effort?.rpe ?? 8
        case .assistance: return unit.display(kg: WorkoutStore.assistanceKg(set, style: .assisted) ?? 0)
        case .distance: return (set.cardioMeters ?? 0) / preferences.distanceUnit.meters
        }
    }

    private var crownStep: Double {
        CrownDetents.step(for: focus ?? .reps, exercise: entry.exercise, unit: preferences.weightUnit)
    }

    private var crownRange: ClosedRange<Double> { CrownDetents.range(for: focus ?? .reps) }

    private func applyCrown(_ value: Double) {
        guard let focus else { return }
        write(field: focus, value: value)
    }

    /// VoiceOver's swipe up / down on a stepper: one crown detent either way, clamped to the
    /// crown's own range, without moving crown focus.
    private func adjust(field: CrownField, direction: AccessibilityAdjustmentDirection) {
        guard let set = currentSet else { return }
        let step = CrownDetents.step(for: field, exercise: entry.exercise, unit: preferences.weightUnit)
        let range = CrownDetents.range(for: field)
        let current = crownValue(for: field, set: set)
        let next = direction == .increment ? current + step : current - step
        write(field: field, value: min(range.upperBound, max(range.lowerBound, next)))
        if focus == field { crown = next }
        Haptics.step()
    }

    private func write(field: CrownField, value: Double) {
        let unit = preferences.weightUnit
        store.updateSet(exerciseID: entry.id) { set in
            switch field {
            case .weight: set.weightKg = unit.toKg(value)
            case .reps: set.reps = Int(value.rounded()) * (entry.exercise.isPerSide ? 2 : 1)
            case .effort: set.effort = Effort(rpe: value)
            case .assistance: set.weightKg = unit.toKg(value)
            case .distance:
                let meters = value * preferences.distanceUnit.meters
                if set.isDone { set.distanceMeters = meters } else { set.targetDistanceMeters = meters }
            }
        }
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
