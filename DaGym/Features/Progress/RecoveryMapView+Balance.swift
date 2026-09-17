import GymCore
import SwiftUI

/// The muscle map's Balance mode, under the hero card: the week / month / all-time window and
/// the "hard sets only" switch (the same `WorkoutStore.bodySeries` aggregation the coach's
/// `get_muscle_volume` reads), plus the untrained list that was always here.
struct BalanceMapSection: View {
    var bundle: WorkoutStore.BodySeriesBundle?
    var snapshot: RecoverySnapshot
    @Binding var window: BalanceHorizon
    @Binding var hardOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            controls
            BalanceSection(
                untrainedMuscles: snapshot.untrainedMuscles, restedMuscles: snapshot.detrainedMuscles
            )
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            ProgressSegmentControl(
                selection: $window, title: \.title,
                accessibilityID: { "recovery.window.\($0.rawValue)" }, controlLabel: "Window"
            )
            .accessibilityIdentifier(A11yID.recoveryWindow)
            Toggle("Hard sets only", isOn: $hardOnly)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .tint(DGColor.coral)
                .accessibilityIdentifier(A11yID.recoveryHardSets)
                .accessibilityHint(Self.hardSetsHint)
            Text(caption)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
    }

    /// Why the figure is blank, when it is — a window with no sets, or "hard only" with nothing
    /// rated — rather than an inert body that looks like a bug.
    private var caption: String {
        guard let bundle else { return "Loading…" }
        let total = bundle.setsPerMuscle.values.reduce(0, +)
        if hardOnly, bundle.ratedSetsInWindow == 0 {
            return "No sets rated \(window.inPhrase). Rate RPE as you log, or turn off Hard sets only."
        }
        if total == 0 { return "No sets logged \(window.inPhrase)." }
        return "\(hardOnly ? "Hard sets" : "Sets") per muscle \(window.inPhrase) · darker means more."
    }

    /// The toggle's rule in words, from the one constant that defines it.
    static let hardSetsHint =
        "Counts only sets rated RPE \(10 - TrainingConstants.hardSetMaxRIR) or higher, or taken to failure"

    /// "12 sets" / "4.5 sets" — a secondary mover's half share can leave a fraction.
    static func setsLabel(_ sets: Double) -> String {
        let rounded = (sets * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return "\(text) \(rounded == 1 ? "set" : "sets")"
    }
}

/// The horizons the Balance map can be drawn over.
enum BalanceHorizon: String, CaseIterable, Identifiable {
    case week, month, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .all: "All time"
        }
    }

    /// "this week" / "in the last 30 days" / "so far" — for the caption.
    var inPhrase: String {
        switch self {
        case .week: "this week"
        case .month: "in the last 30 days"
        case .all: "so far"
        }
    }

    /// "the week" / "the month" / "the load" — "Chest is carrying …" in the hero headline.
    var carryingPhrase: String {
        switch self {
        case .week: "the week"
        case .month: "the month"
        case .all: "the load"
        }
    }

    /// `.thisWeek` takes the training calendar so the week starts where Home's does.
    func window(calendar: Calendar) -> BalanceWindow {
        switch self {
        case .week: .thisWeek(calendar)
        case .month: .days(30)
        case .all: .allTime
        }
    }
}

/// What hasn't been trained: the "not this week" tags, plus the graded longest-without-work
/// list the snapshot already computes. Strictly descriptive — how long it has been, never a
/// claim about what that time off has done to the lifter.
struct BalanceSection: View {
    var untrainedMuscles: [Muscle]
    var restedMuscles: [MuscleRetention]

    /// Enough to be useful, short enough that a lifter two weeks off training doesn't get a
    /// wall of every muscle they own.
    private static let maxListed = 4

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            ProgressCardTitle(title: "Balance")
            thisWeek
            if !listed.isEmpty { longestWithoutWork }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
    }

    @ViewBuilder
    private var thisWeek: some View {
        if untrainedMuscles.isEmpty {
            Text("Every muscle group has seen work this week.")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        } else {
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Not trained this week")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
                RecoveryFlowLayout(spacing: DGSpace.s2) {
                    ForEach(untrainedMuscles) { muscle in
                        DGTag(text: muscle.displayName)
                    }
                }
            }
        }
    }

    /// Only muscles this lifter has actually trained at some point: one they have never trained
    /// has nothing to say beyond the "not trained this week" tag it already carries, and a brand
    /// new account would otherwise get a list of four "No sets logged" rows.
    private var listed: [MuscleRetention] {
        Array(restedMuscles.filter { $0.lastTrained != nil }.prefix(Self.maxListed))
    }

    private var longestWithoutWork: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Longest without work")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
            ForEach(listed) { rested in
                HStack {
                    Text(rested.muscle.displayName)
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink2)
                    Spacer()
                    Text(Self.sinceLabel(rested.lastTrained))
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                .frame(minHeight: 28)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "3 weeks ago" / "18 days ago" / "No sets logged" — the fact, not an interpretation of it.
    static func sinceLabel(_ lastTrained: Date?) -> String {
        guard let lastTrained else { return "No sets logged" }
        return lastTrained.formatted(.relative(presentation: .numeric))
    }
}

/// Simple left-to-right, top-to-bottom wrap for the balance tags.
struct RecoveryFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > width, origin.x > 0 {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += size.width + spacing
            maxWidth = max(maxWidth, origin.x)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: origin.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
