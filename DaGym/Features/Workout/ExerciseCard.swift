import GymCore
import SwiftUI

/// One exercise in the active workout list. Renders one of three layouts:
/// on-deck (full card with sets), collapsed incomplete row, or a completed
/// one-liner. See mockups 02_00 / 02_01 and design sheet 01_04.
struct ExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var isOnDeck: Bool
    var effortScale: Effort.Scale
    var onTapWeight: (UUID) -> Void
    var onTapReps: (UUID) -> Void
    var onTapEffort: (UUID) -> Void
    var onToggleDone: (SetEntry) -> Void
    var onMore: () -> Void
    var onStartTimed: (UUID) -> Void
    /// Note button in the on-deck header, and the set-row swipe actions.
    var onNote: () -> Void = {}
    var onDeleteSet: (UUID) -> Void = { _ in }
    var onChangeSetKind: (UUID, SetKind) -> Void = { _, _ in }

    var body: some View {
        if entry.isComplete {
            CompletedExerciseRow(entry: entry)
        } else if isOnDeck {
            OnDeckExerciseCard(
                entry: entry, effortScale: effortScale,
                onTapWeight: onTapWeight, onTapReps: onTapReps, onTapEffort: onTapEffort,
                onToggleDone: onToggleDone, onMore: onMore, onStartTimed: onStartTimed, onNote: onNote,
                onDeleteSet: onDeleteSet, onChangeSetKind: onChangeSetKind
            )
        } else {
            CollapsedExerciseRow(entry: entry, onStartTimed: onStartTimed)
        }
    }
}

/// Which rows the on-deck card lays out: weight × reps `SetRow`s, or one `TimedSetRow` per hold
/// with Start on the next open one. Pure so it can be asserted without rendering the card.
enum OnDeckRows: Equatable {
    case loaded
    case timed(startSetID: UUID?)
}

extension WorkoutExerciseEntry {
    var nextOpenSetID: UUID? { sets.first { !$0.isDone }?.id }

    var onDeckRows: OnDeckRows {
        isTimed ? .timed(startSetID: nextOpenSetID) : .loaded
    }
}

/// The detailed, fully expanded card for the exercise currently being worked.
private struct OnDeckExerciseCard: View {
    var entry: WorkoutExerciseEntry
    var effortScale: Effort.Scale
    var onTapWeight: (UUID) -> Void
    var onTapReps: (UUID) -> Void
    var onTapEffort: (UUID) -> Void
    var onToggleDone: (SetEntry) -> Void
    var onMore: () -> Void
    var onStartTimed: (UUID) -> Void
    var onNote: () -> Void
    var onDeleteSet: (UUID) -> Void
    var onChangeSetKind: (UUID, SetKind) -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("On deck").dgLabel(DGColor.coralText)
                .padding(.horizontal, DGSpace.s2)
                .padding(.vertical, 4)
                .background(DGColor.coralWash, in: Capsule())
                .padding(.bottom, DGSpace.s2)
            header
            if !entry.lastSessions.isEmpty {
                lastSessionsStrip.padding(.top, DGSpace.s4)
            }
            if let whyTitle = entry.whyTitle, let whyBody = entry.whyBody {
                WhyCard(title: whyTitle, message: whyBody, labelColor: whyLabelColor)
                    .padding(.top, DGSpace.s3)
            }
            switch entry.onDeckRows {
            case .loaded:
                columnHeader.padding(.top, DGSpace.s4)
                setRows.padding(.top, DGSpace.s2)
            case .timed(let startSetID):
                timedColumnHeader.padding(.top, DGSpace.s4)
                timedRows(startSetID: startSetID).padding(.top, DGSpace.s2)
            }
        }
        .dgCard()
    }

    private var header: some View {
        HStack(spacing: DGSpace.s3) {
            ExerciseThumbnail(exercise: entry.exercise)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise.name)
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text(footnote)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer(minLength: 0)
            DGIconButton(symbol: "text.bubble", size: 36, tint: DGColor.ink2, action: onNote)
            DGIconButton(symbol: "ellipsis", action: onMore)
        }
    }

    private var whyLabelColor: Color {
        entry.whyKind == .deload ? DGColor.warning : DGColor.aiVioletText
    }

    private var footnote: String {
        let step = entry.doneCount + 1 <= entry.sets.count ? entry.doneCount + 1 : entry.sets.count
        let rest = WorkoutSession.clock(entry.exercise.restSeconds)
        let incrementValue = preferences.formatWeight(kg: entry.exercise.incrementKg)
        let increment = "\(incrementValue) \(preferences.unitSymbol)"
        return "Set \(step) of \(entry.sets.count) · rest \(rest) · increment \(increment)"
    }

    private var lastSessionsStrip: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Last 3 sessions").dgLabel()
            HStack(spacing: DGSpace.s3) {
                Text(entry.lastSessions.joined(separator: " · "))
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink2)
                Spacer(minLength: DGSpace.s2)
                Sparkline(values: entry.sparkline)
                    .frame(width: 60, height: 22)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text("Set").frame(width: 28, alignment: .leading)
            Text("Prev").frame(minWidth: 44, alignment: .leading)
            Text(preferences.unitSymbol.uppercased()).frame(minWidth: 44, alignment: .leading)
            Text("Reps").frame(minWidth: 30, alignment: .leading)
            Text(effortScale == .rpe ? "Rpe" : "Rir").frame(width: 28, alignment: .leading)
        }
        .dgLabel()
    }

    private var timedColumnHeader: some View {
        HStack(spacing: DGSpace.s3) {
            Text("Set").frame(width: 28, alignment: .leading)
            Text("Target").frame(minWidth: 44, alignment: .leading)
            Text("Held").frame(minWidth: 44, alignment: .leading)
        }
        .dgLabel()
    }

    private func timedRows(startSetID: UUID?) -> some View {
        VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                TimedSetRow(
                    set: set, badgeIndex: workingIndex(upTo: index), isCurrent: set.id == startSetID,
                    onStart: { onStartTimed(set.id) }, onToggleDone: { onToggleDone(set) }
                )
            }
        }
    }

    private var setRows: some View {
        let firstOpenID = entry.nextOpenSetID
        return VStack(spacing: DGSpace.s2) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    set: set, badgeIndex: workingIndex(upTo: index), rowIndex: index,
                    isCurrent: set.id == firstOpenID,
                    effortScale: effortScale, isPerSide: entry.exercise.isPerSide,
                    onTapWeight: { onTapWeight(set.id) }, onTapReps: { onTapReps(set.id) },
                    onTapEffort: { onTapEffort(set.id) }, onToggleDone: { onToggleDone(set) },
                    onDelete: { onDeleteSet(set.id) },
                    onChangeKind: { kind in onChangeSetKind(set.id, kind) }
                )
            }
        }
    }

    private func workingIndex(upTo index: Int) -> Int {
        entry.sets.prefix(index + 1).filter { $0.kind == .working }.count
    }
}

/// Collapsed one-line row for an incomplete exercise that isn't on deck yet.
private struct CollapsedExerciseRow: View {
    var entry: WorkoutExerciseEntry
    var onStartTimed: (UUID) -> Void

    @Environment(Preferences.self) private var preferences

    private var firstOpenSetID: UUID? { entry.nextOpenSetID ?? entry.sets.first?.id }

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            ExerciseThumbnail(exercise: entry.exercise, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise.name)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text(summaryLine)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            Spacer(minLength: DGSpace.s2)
            if entry.isTimed {
                Button {
                    if let setID = firstOpenSetID { onStartTimed(setID) }
                } label: {
                    Text("Start")
                        .font(DGFont.condensedLabel(12))
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                        .padding(.horizontal, DGSpace.s3)
                        .frame(height: 36)
                        .dgGlass(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("\(entry.doneCount)/\(entry.sets.count)")
                    .dgMetric(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .dgCard(padding: DGSpace.s4)
    }

    private var summaryLine: String {
        guard let first = entry.sets.first else { return entry.exercise.equipment }
        if entry.isTimed {
            let target = first.targetSeconds ?? 0
            return "\(entry.sets.count) holds · target \(WorkoutSession.clock(target))"
        }
        let weight = preferences.formatWeight(kg: first.weightKg)
        let suffix = entry.exercise.isPerSide ? "\(preferences.unitSymbol) per side" : preferences.unitSymbol
        return "\(entry.sets.count) × \(first.reps) · \(weight) \(suffix)"
    }
}

/// One-liner for a finished exercise.
private struct CompletedExerciseRow: View {
    var entry: WorkoutExerciseEntry

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Completed").dgLabel(DGColor.success)
            Text(summary)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(padding: DGSpace.s4)
    }

    private var summary: String {
        let name = entry.exercise.name.uppercased()
        guard let first = entry.sets.first else { return name }
        if entry.isTimed {
            let best = entry.sets.compactMap(\.durationSeconds).max() ?? 0
            return "\(name) · \(entry.sets.count) holds · best \(WorkoutSession.clock(best))"
        }
        let weight = preferences.formatWeight(kg: first.weightKg)
        return "\(name) · \(entry.sets.count) × \(first.reps) · \(weight) \(preferences.unitSymbol)"
    }
}

private struct ExerciseThumbnail: View {
    var exercise: ExerciseInfo
    var size: CGFloat = 44

    var body: some View {
        BodyMapView(side: .front, mode: .hit, intensity: exercise.hitMap)
            .padding(6)
            .frame(width: size, height: size)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
    }
}

/// Tiny trend line drawn from raw values, coral stroke.
private struct Sparkline: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let span = max(high - low, 0.001)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = values.count > 1
                        ? geo.size.width * CGFloat(index) / CGFloat(values.count - 1) : 0
                    let y = geo.size.height * (1 - CGFloat((value - low) / span))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(DGColor.coral, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: DGSpace.s4) {
            ForEach(SampleData.makeSession().exercises) { entry in
                ExerciseCard(
                    entry: entry, isOnDeck: entry.exercise.id == SampleData.bench.id, effortScale: .rpe,
                    onTapWeight: { _ in }, onTapReps: { _ in }, onTapEffort: { _ in },
                    onToggleDone: { _ in }, onMore: {}, onStartTimed: { _ in }
                )
            }
        }
        .padding()
    }
    .background(AmbientWash())
    .environment(Preferences())
}
