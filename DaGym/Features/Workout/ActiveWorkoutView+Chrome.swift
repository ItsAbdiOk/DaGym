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
    /// exercise. `compactWorkoutLayout` is remembered in `Preferences`.
    var headerMenu: some View {
        @Bindable var prefs = preferences
        return Menu {
            Toggle(
                "Compact layout", systemImage: "rectangle.compress.vertical",
                isOn: $prefs.compactWorkoutLayout
            )
            Button("Add routine…", systemImage: "list.bullet.rectangle") { activeSheet = .addRoutine }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .frame(width: 44, height: 44)
                .dgGlass(.regular, in: Circle())
        }
        .accessibilityLabel("Workout options")
    }

    /// Single 40pt row: title + elapsed on one line, FINISH shrunk to a 36pt pill.
    var condensedNavHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text(session.title)
                .font(DGFont.title3)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
            Spacer(minLength: DGSpace.s2)
            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                Text(WorkoutSession.clock(session.elapsedSeconds(at: context.date)))
                    .dgMetric(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            Button("Finish") { showFinishConfirm = true }
                .buttonStyle(.plain)
                .font(DGFont.condensedLabel(13))
                .textCase(.uppercase)
                .foregroundStyle(DGColor.inkOnCoral)
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 36)
                .background(DGColor.coral, in: Capsule())
                .accessibilityIdentifier(A11yID.workoutFinish)
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(height: 40)
        .dgGlass(.regular, radius: 0)
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
            if session.isResting {
                RestPillCompact(remaining: session.restRemaining, total: session.restTotal)
            }
            Spacer(minLength: 0)
            Button { activeSheet = .addExercise } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(width: 52, height: 52)
                    .background(DGColor.coral, in: Circle())
                    .shadow(color: DGColor.coral.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(DGPressStyle())
            .accessibilityLabel("Add exercise")
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s2)
    }
}
