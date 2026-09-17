import GymCore
import SwiftData
import SwiftUI

/// The Train tab: a "Train" title over a three-way switch — Routines (a card per saved routine
/// with a Start pill), Programs (`ProgramsView`) and Schedule (`ScheduleView`). Train is a root
/// tab, so it keeps its own `NavigationStack`: the builder, the exercise library and Settings
/// push onto it.
struct RoutinesTabView: View {
    var onStart: (RoutineInfo) -> Void

    @Environment(WorkoutStore.self) private var store
    @State private var routines: [RoutineInfo] = []
    @State private var activeProfile: EquipmentProfileInfo?
    @State private var path = NavigationPath()
    @State private var segment = TrainSegment.initial
    @State private var askingCoach = false
    /// The "Load a starter plan" sheet — the same `StarterPlanList` Home's empty-state card shows.
    @State private var pickingStarterPlan = false

    private enum Destination: Hashable {
        case edit(UUID)
        case new
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AmbientWash()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Train")
                            .font(DGFont.title1)
                            .foregroundStyle(DGColor.ink1)
                            .padding(.horizontal, DGSpace.s1)
                        TrainSegmentControl(selection: $segment)
                        content
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 110)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { destination in
                // The builder draws its own Cancel/Save row, so the system bar (and its back
                // button) would only double up.
                Group {
                    switch destination {
                    case .edit(let id):
                        RoutineBuilderView(routineID: id, onDone: pop)
                    case .new:
                        RoutineBuilderView(routineID: nil, onDone: pop)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            // The Schedule segment's library row and its "Settings → Calendar" link reuse the
            // You hub's destinations, so the same screen is one push deep from either tab.
            .navigationDestination(for: YouDestination.self) { destination in
                destination.screen
            }
            .task { refresh() }
            .refreshOnStoreChange(refresh)
        }
        .askCoach(on: $askingCoach)
        .sheet(isPresented: $pickingStarterPlan) {
            StarterPlanPickerSheet(onPick: adoptStarterPlan)
        }
        .dgWarmHaptics()
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .routines:
            routineList
        case .programs:
            ProgramsView()
        case .schedule:
            ScheduleView(onPush: { path.append($0) })
        }
    }

    @ViewBuilder
    private var routineList: some View {
        if routines.isEmpty {
            // The app ships no routines. The real paths: build one by hand, let the coach build
            // one from a sentence, or adopt a starter plan (the same picker Home's empty card
            // shows) which seeds its routines and starts the program.
            EmptyState(
                symbol: "dumbbell", title: "No routines yet",
                message: "Build one, let the coach write one for you, or load a starter plan.",
                action: "New routine", onAction: { path.append(Destination.new) },
                secondaryAction: "Let the coach build one", onSecondaryAction: { askingCoach = true }
            )
            .accessibilityIdentifier(A11yID.trainNewRoutine)
            Button("Load a starter plan") { pickingStarterPlan = true }
                .buttonStyle(.dgControl)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.coralText)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(A11yID.routinesStarterPlan)
        } else {
            VStack(spacing: 10) {
                ForEach(routines) { routine in
                    // Start sits *over* the card button, never inside its label: a button nested
                    // in a button is undefined for hit-testing and unreachable for VoiceOver.
                    Button { path.append(Destination.edit(routine.id)) } label: {
                        RoutineCard(
                            routine: routine, missingEquipment: missingEquipment(for: routine),
                            profileName: activeProfile?.name ?? ""
                        )
                    }
                    .buttonStyle(.dgCard)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { path.append(Destination.edit(routine.id)) }
                        Button("Duplicate", systemImage: "doc.on.doc") { duplicate(routine) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(routine) }
                    }
                    .overlay(alignment: .topTrailing) {
                        RoutineStartPill(routineName: routine.name) { onStart(routine) }
                            .padding(15)
                    }
                }
                TrainDashedButton(title: "New routine") { path.append(Destination.new) }
                    .padding(.top, 2)
                    .accessibilityIdentifier(A11yID.trainNewRoutine)
            }
        }
    }

    private func refresh() {
        routines = store.routines()
        activeProfile = store.activeProfile()
    }

    /// Equipment kinds and stations the routine needs that the active profile lacks, as the
    /// names the badge prints; empty when there's no profile or it lists everything, so a fresh
    /// install never shows a badge.
    private func missingEquipment(for routine: RoutineInfo) -> [String] {
        guard let activeProfile, activeProfile.restrictsLibrary else { return [] }
        return routine.needs(outside: activeProfile.availability).displayNames
    }

    /// Seeds the plan's routines and starts its program, exactly as Home's card does
    /// (`WorkoutStore.adoptStarterPlan`); `refresh` fills this tab with the new routines.
    private func adoptStarterPlan(_ kind: StarterProgramKind) {
        store.adoptStarterPlan(kind)
        refresh()
    }

    private func duplicate(_ routine: RoutineInfo) {
        store.duplicateRoutine(id: routine.id)
        refresh()
    }

    private func pop() {
        if !path.isEmpty { path.removeLast() }
        refresh()
    }

    private func delete(_ routine: RoutineInfo) {
        store.deleteRoutine(id: routine.id)
        refresh()
    }
}

/// One routine card from the prototype: a tinted glyph square, name over "58 min · 6
/// exercises · 22 sets", the exercise names as one dim line, and — when the active equipment
/// profile can't cover it — a warm "Needs a leg press — not in Home" badge. The Start pill's
/// footprint is reserved top-right; `RoutinesTabView` overlays the live button.
private struct RoutineCard: View {
    var routine: RoutineInfo
    var missingEquipment: [String] = []
    var profileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: DGSpace.s3) {
                RoutineGlyph(symbolName: routine.symbolName, tint: routine.tint, size: 40, filled: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                        .lineLimit(1)
                    Text(meta)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .monospacedDigit()
                }
                Spacer(minLength: DGSpace.s2)
                RoutineStartPill(routineName: routine.name, action: {}).hidden()
            }
            .accessibilityElement(children: .combine)
            Text(exerciseNames)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !missingEquipment.isEmpty {
                equipmentBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: DGRadius.lg, padding: 15)
    }

    private var meta: String {
        let exercises = routine.exercises.count == 1 ? "1 exercise" : "\(routine.exercises.count) exercises"
        let sets = routine.setCount == 1 ? "1 set" : "\(routine.setCount) sets"
        return "\(routine.estimatedMinutes) min · \(exercises) · \(sets)"
    }
}

/// The accent "Start" pill on a routine card, overlaid by `RoutinesTabView` so it is a sibling
/// of the card button rather than a button inside a button.
private struct RoutineStartPill: View {
    var routineName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Start")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DGColor.inkOnCoral)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(DGColor.coral, in: Capsule())
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Start \(routineName)")
    }
}

extension RoutineCard {
    /// Amber on a warm wash — `prGoldText` is the one amber token stepped for small text.
    private var equipmentBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(DGColor.warning).frame(width: 6, height: 6)
            Text("Needs \(missingNames) — not in \(profileName)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DGColor.prGoldText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(DGColor.warning.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Needs \(missingNames), not in the \(profileName) profile")
    }

    /// `missingEquipment` is already display names (`EquipmentNeeds.displayNames`).
    private var missingNames: String { missingEquipment.joined(separator: ", ") }

    private var exerciseNames: String { routine.exercises.map(\.name).joined(separator: " · ") }
}

extension TrainSegment {
    /// The segment the tab opens on. `-dgTrainSegment programs` (screenshot mode only) lets the
    /// App Store screenshot build and a UI test land on Programs or Schedule directly.
    static var initial: TrainSegment {
        guard LaunchFlags.isScreenshotting else { return .routines }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-dgTrainSegment"), index + 1 < args.count else {
            return .routines
        }
        let wanted = args[index + 1].lowercased()
        return TrainSegment.allCases.first { $0.rawValue.lowercased() == wanted } ?? .routines
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        RoutinesTabView(onStart: { _ in })
            .environment(WorkoutStore(context: container.mainContext))
    } else {
        Text("Preview unavailable")
    }
}
