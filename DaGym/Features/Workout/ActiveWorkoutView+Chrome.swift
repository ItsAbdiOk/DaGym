import GymCore
import SwiftUI

/// The sticky header from the redesign prototype: a round chevron (minimise — the cover drops
/// and the session carries on behind the tab bar's resume strip), "Push · Heavy" over
/// "25:00 · Wed 17 Sep", the "…" workout-options menu, the hold-to-talk mic and the accent
/// "Finish" pill, then three frosted stat tiles. Scrolling down past a threshold sheds the tiles and
/// condenses the row (`ChromeCollapseState` owns the threshold + hysteresis math); scrolling
/// back up restores them.
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

    /// The chevron: minimise, where the shell offers it (`onMinimise`). A backfill or debug
    /// cover has nowhere to minimise to, so the chevron is simply absent there.
    @ViewBuilder var minimiseButton: some View {
        if let onMinimise {
            Button(action: onMinimise) {
                WorkoutRoundGlyph(symbol: "chevron.down", size: 32)
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Minimise workout")
            .accessibilityHint("Keeps the workout running behind the tabs")
            .accessibilityIdentifier(A11yID.workoutMinimise)
        }
    }

    /// The "…" menu: layout and session-level additions that don't belong on any one
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
            WorkoutRoundGlyph(symbol: "ellipsis", size: 32)
        }
        .accessibilityLabel("Workout options")
        .accessibilityIdentifier(A11yID.workoutOptions)
    }

    /// Reads the effective layout; writes only the session override.
    private var layoutBinding: Binding<WorkoutLayout> {
        Binding(get: { layout }, set: { layoutOverride = $0 })
    }

    // MARK: Expanded header

    var navHeader: some View {
        VStack(spacing: DGSpace.s3) {
            headerRow
            statTiles
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.top, DGSpace.s2)
        .padding(.bottom, DGSpace.s3)
        .background(headerBackdrop)
    }

    /// `rgba(246,243,239,.78)` over a blur with a hairline underneath — the page colour, not a
    /// glass pill, so it reads as the page continuing rather than a floating bar.
    private var headerBackdrop: some View {
        DGColor.bgBase.opacity(0.78)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider().overlay(DGColor.hairline) }
            .ignoresSafeArea(edges: .top)
    }

    private var headerRow: some View {
        // Title on its own line at accessibility sizes; the controls become a second row.
        DGAdaptiveStack(verticalAlignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                minimiseButton
                titleBlock
            }
            Spacer(minLength: DGSpace.s2)
            headerControls
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
            HStack(spacing: 0) {
                if !session.isBackfilled {
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        Text(WorkoutSession.clock(session.elapsedSeconds(at: context.date)))
                            .monospacedDigit()
                    }
                    Text(" · ")
                }
                Text(startedAtLabel)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(DGColor.ink3)
        }
        .accessibilityElement(children: .combine)
    }

    var headerControls: some View {
        HStack(spacing: DGSpace.s2) {
            headerMenu
            // Voice logging entry point (plan: DaGym/Features/Voice). The controller is the
            // screen's (`voiceController`), owned once for the whole workout.
            if let voiceController {
                VoiceLogEntryPoint(
                    session: session, store: store, preferences: preferences, controller: voiceController,
                    undoAction: $undoAction
                )
            }
            finishPill
        }
        .fixedSize(horizontal: true, vertical: false)
        .dgDenseType()
    }

    private var finishPill: some View {
        Button("Finish") { showFinishConfirm = true }
            .buttonStyle(.dgControl)
            .font(DGFont.condensedLabel(13.5))
            .foregroundStyle(DGColor.inkOnCoral)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(DGColor.coral, in: Capsule())
            .accessibilityIdentifier(A11yID.workoutFinish)
    }

    /// "VOLUME 2.2 t · SETS 4 / 19 · PRS 1" — three flat tiles, kicker over a 15 pt tabular value.
    var statTiles: some View {
        let volume = Self.volumeTile(kg: session.volumeKg, preferences: preferences)
        return DGAdaptiveStack(spacing: DGSpace.s2, threshold: .accessibility3) {
            WorkoutStatTile(kicker: "Volume", value: volume.value, suffix: volume.suffix)
            WorkoutStatTile(kicker: "Sets", value: "\(session.setsDone) / \(session.setsTotal)")
            WorkoutStatTile(kicker: "PRs", value: "\(session.prCount)")
        }
    }

    /// Session volume for the tile: tonnes to one decimal for a kg lifter ("2.2 t" fits where
    /// "2 240 kg" wraps); the grouped pound total for a lb lifter, since pounds have no tonne.
    static func volumeTile(kg: Double, preferences: Preferences) -> (value: String, suffix: String) {
        guard preferences.weightUnit == .kg else {
            return (preferences.formatVolume(kg: kg), preferences.unitSymbol)
        }
        return (String(format: "%.1f", (kg / 100).rounded() / 10), "t")
    }

    /// Single 40pt row: title + elapsed on one line, "…" and Finish shrunk beside it.
    var condensedNavHeader: some View {
        HStack(spacing: DGSpace.s3) {
            minimiseButton
            Text(session.title)
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
            Spacer(minLength: DGSpace.s2)
            if !session.isBackfilled {
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(WorkoutSession.clock(session.elapsedSeconds(at: context.date)))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(DGColor.ink3)
                }
            }
            headerMenu
            finishPill
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.vertical, DGSpace.s2)
        .background(headerBackdrop)
        .dgDenseType()
    }

    /// The floating bottom chrome: only the rest pill, in either scroll state. The list's own
    /// "Add exercise / Reorder" pills sit at the end of the scroll, as in the prototype.
    var bottomChrome: some View {
        RestPillSection(session: session)
            .padding(.horizontal, DGSpace.s4)
            .padding(.bottom, DGSpace.s3)
    }
}

/// One of the header's three tiles: an 11 pt uppercase kicker over a 15 pt semibold value.
struct WorkoutStatTile: View {
    var kicker: String
    var value: String
    var suffix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker).dgLabel()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DGColor.ink3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .dgTile(radius: 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value)\(suffix.map { " \($0)" } ?? ""), \(kicker)")
    }
}
