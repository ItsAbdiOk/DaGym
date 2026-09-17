import SwiftUI

/// The three faces of "This week". Raw values are the segment labels.
enum ThisWeekSegment: String, CaseIterable, Identifiable {
    case trends = "Trends"
    case records = "Records"
    case consistency = "Consistency"

    var id: String { rawValue }
}

/// "This week", pushed from the Progress hub: Trends (the delta tiles and body-wide charts),
/// Records (every personal record as a row, then milestones) and Consistency (streaks and the
/// heatmap). Each segment reads the store only once it is shown.
struct ThisWeekView: View {
    @Environment(WorkoutStore.self) private var store
    @State private var segment: ThisWeekSegment
    /// Bumped on every store save while the screen is showing, so a delete or backfill elsewhere
    /// in the stack re-reads the series when the lifter comes back.
    @State private var generation = 0

    init(initialSegment: ThisWeekSegment = .trends) {
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    ProgressSegmentControl(
                        selection: $segment, title: \.rawValue,
                        accessibilityID: { A11yID.thisWeekSegment($0.rawValue) },
                        controlLabel: "This week section"
                    )
                    .padding(.bottom, 2)
                    switch segment {
                    case .trends:
                        ProgressChartsSection(generation: generation)
                    case .records:
                        RecordsSection(generation: generation)
                    case .consistency:
                        ConsistencySection(generation: generation)
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .refreshOnStoreChange { generation += 1 }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack { ThisWeekView() }
            .environment(store)
            .environment(Preferences())
    }
}
