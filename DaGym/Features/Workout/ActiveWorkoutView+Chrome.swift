import GymCore
import SwiftUI

/// "Chrome sheds on scroll" (mockups 02_00/02_01): scrolling down past a threshold condenses
/// the nav to a single 40pt row and slides the action bar away, leaving a compact rest pill
/// plus a coral "+" satellite; scrolling back up restores everything. `ChromeCollapseState`
/// owns the threshold + hysteresis math — this file just renders its two states.
extension ActiveWorkoutView {
    /// Feeds a new `contentOffset.y` reading into `chromeCollapse`, animating only when the
    /// collapsed/expanded state actually flips.
    func updateChrome(offset: CGFloat) {
        var next = chromeCollapse
        guard next.update(offset: offset) else {
            chromeCollapse = next
            return
        }
        withAnimation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion)) { chromeCollapse = next }
    }

    /// The "…" next to FINISH: layout and session-level additions that don't belong on any one
    /// exercise. The layout picker is a per-session override of `Preferences.workoutLayout`
    /// (the saved default lives in Settings › Workout); the steppers toggle is remembered.
    var headerMenu: some View {
        @Bindable var prefs = preferences
        return Menu {
            Picker("Layout", selection: layoutBinding) {
                ForEach(WorkoutLayout.allCases) { layout in
                    Label(layout.title, systemImage: layout.symbolName).tag(layout)
                }
            }
            .pickerStyle(.menu)
            // `SetRow` has always read `showSetSteppers`, but nothing wrote it — the ± buttons
            // were unreachable. This is its home, next to the other layout switch.
            Toggle(
                "Set steppers", systemImage: "plusminus",
                isOn: $prefs.showSetSteppers
            )
            Button("Add routine…", systemImage: "list.bullet.rectangle") {
                addRoutineChoices = store.routines()
                activeSheet = .addRoutine
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .frame(width: 44, height: 44)
                .dgGlass(.regular, in: Circle())
        }
        .accessibilityLabel("Workout options")
    }

    /// Reads the effective layout; writes only the session override.
    private var layoutBinding: Binding<WorkoutLayout> {
        Binding(get: { layout }, set: { layoutOverride = $0 })
    }

    // MARK: Expanded header

    var navHeader: some View {
        // Title on its own line at accessibility sizes; the controls become a second row.
        DGAdaptiveStack(verticalAlignment: .top, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(startedAtLabel).dgLabel()
                Text(session.title)
                    .font(DGFont.title1)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer(minLength: DGSpace.s2)
            headerControls
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.top, DGSpace.s2)
        .padding(.bottom, DGSpace.s3)
        .dgGlass(.regular, radius: 0)
    }

    var headerControls: some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            if !session.isBackfilled {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Elapsed").dgLabel()
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        Text(WorkoutSession.clock(session.elapsedSeconds(at: context.date)))
                            .dgMetric(DGFont.metricL)
                            .foregroundStyle(DGColor.ink1)
                    }
                }
                // The clock never compresses; the title on the other side of the row wraps.
                .fixedSize()
            }
            DGPrimaryButton(title: "Finish", height: 44) { showFinishConfirm = true }
                .frame(width: 96)
                .accessibilityIdentifier(A11yID.workoutFinish)
            // Voice logging entry point (plan: DaGym/Features/Voice). The controller is the
            // screen's (`voiceController`), owned once for the whole workout.
            if let voiceController {
                VoiceLogEntryPoint(
                    session: session, store: store, preferences: preferences, controller: voiceController,
                    undoAction: $undoAction
                )
            }
            headerMenu
        }
        .fixedSize(horizontal: true, vertical: false)
        .dgDenseType()
    }

    var statStrip: some View {
        DGAdaptiveStack(spacing: 0, threshold: .accessibility3) {
            StatTile(
                value: preferences.formatWeight(kg: session.volumeKg),
                label: "\(preferences.unitSymbol) volume"
            )
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

    /// Single 40pt row: title + elapsed on one line, FINISH shrunk to a 36pt pill.
    var condensedNavHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text(session.title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
            Spacer(minLength: DGSpace.s2)
            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                Text(WorkoutSession.clock(session.elapsedSeconds(at: context.date)))
                    .dgMetric(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            Button("Finish") { showFinishConfirm = true }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .foregroundStyle(DGColor.inkOnCoral)
                .padding(.horizontal, DGSpace.s3)
                .frame(minHeight: 36)
                .background(DGColor.coral, in: Capsule())
                .accessibilityIdentifier(A11yID.workoutFinish)
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 40)
        .dgGlass(.regular, radius: 0)
        .dgDenseType()
    }

    /// The bottom sticky group, swapped between the full action bar and the condensed
    /// rest-pill + "+" satellite as `chromeCollapse` flips.
    @ViewBuilder
    var bottomChrome: some View {
        if chromeCollapse.isCollapsed {
            condensedBottomGroup
        } else {
            bottomGroup
        }
    }

    /// Compact bottom chrome: rest pill (only while resting) + a single coral "+" satellite
    /// that opens the add-exercise sheet, replacing the full action bar.
    var condensedBottomGroup: some View {
        HStack(spacing: DGSpace.s3) {
            RestPillCompactSection(session: session)
            Spacer(minLength: 0)
            Button { activeSheet = .addExercise } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(width: 52, height: 52)
                    .background(DGColor.coral, in: Circle())
                    .shadow(color: DGColor.coral.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Add exercise")
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s2)
    }
}
