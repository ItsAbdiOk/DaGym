import GymCore
import SwiftData
import SwiftUI

/// Full recovery map: front/back body heatmap, a muscle-by-muscle fatigue list, and which
/// muscles saw no training this week. Presented as a sheet from Home's "See Map".
struct RecoveryMapView: View {
    @Environment(WorkoutStore.self) private var store
    @State private var snapshot = RecoverySnapshot(map: [:], perMuscle: [], untrainedMuscles: [])
    @State private var selected: MuscleRecovery?

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    mapCard
                    muscleList
                    BalanceSection(untrainedMuscles: snapshot.untrainedMuscles)
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { refresh() }
        .sheet(item: $selected) { muscle in
            MuscleDetailSheet(recovery: muscle)
        }
    }

    private func refresh() {
        snapshot = store.recoverySnapshot()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Recovery")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("Fresh → spent · based on the last 7 days")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    private var mapCard: some View {
        VStack(spacing: DGSpace.s4) {
            HStack(spacing: DGSpace.s4) {
                BodyMapView(side: .front, mode: .recovery, intensity: snapshot.map, onTap: selectMuscle)
                BodyMapView(side: .back, mode: .recovery, intensity: snapshot.map, onTap: selectMuscle)
            }
            .frame(height: 260)
            RecoveryLegend()
        }
        .dgCard()
    }

    private func selectMuscle(_ muscle: Muscle) {
        guard let match = snapshot.perMuscle.first(where: { $0.muscle == muscle }) else { return }
        selected = match
    }

    private var muscleList: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Muscles").dgLabel()
            if snapshot.perMuscle.isEmpty {
                Text("Log a workout to start tracking recovery.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            } else {
                VStack(spacing: DGSpace.s2) {
                    ForEach(snapshot.perMuscle) { muscle in
                        MuscleListRow(recovery: muscle) { selected = muscle }
                    }
                }
            }
        }
    }
}

/// 5-stop "FRESH … SPENT" legend row under the map.
private struct RecoveryLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            HStack(spacing: 4) {
                ForEach(Array(DGColor.recovery.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(height: 6)
                }
            }
            HStack {
                Text("Fresh").dgLabel()
                Spacer()
                Text("Spent").dgLabel()
            }
        }
    }
}

/// One row: muscle name, a fatigue bar in the ramp colour, and when it'll be fresh again.
private struct MuscleListRow: View {
    var recovery: MuscleRecovery
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text(recovery.muscle.displayName)
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(DGColor.surface3)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(rampColor)
                                    .frame(width: geo.size.width * recovery.spent)
                            }
                    }
                    .frame(height: 6)
                }
                Text(statusLabel)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .frame(width: 120, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(DGSpace.s4)
            .frame(minHeight: DGTap.min)
            .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    .strokeBorder(DGColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(DGPressStyle())
    }

    private var rampColor: Color {
        let index = Int((recovery.spent * 4).rounded())
        return DGColor.recovery[min(4, max(0, index))]
    }

    private var statusLabel: String {
        guard let recoveredBy = recovery.recoveredBy else { return "Fresh" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return "Recovered by \(formatter.string(from: recoveredBy))"
    }
}

/// "Not trained this week" tag row, computed from the snapshot's untrained muscles.
private struct BalanceSection: View {
    var untrainedMuscles: [Muscle]

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Balance").dgLabel()
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
        .dgCard()
    }
}

/// Simple left-to-right, top-to-bottom wrap for the balance tags.
private struct RecoveryFlowLayout: Layout {
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

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        RecoveryMapView()
            .environment(WorkoutStore(context: container.mainContext))
    } else {
        Text("Preview unavailable")
    }
}
