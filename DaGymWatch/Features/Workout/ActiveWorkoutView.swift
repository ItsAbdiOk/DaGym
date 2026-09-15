import GymCore
import SwiftUI

/// Screen 2: one page per exercise, swiped left and right, with a last page to finish. Rests
/// over 45 s cover the pages (3B/3C); the record card (5) floats over whatever is showing and
/// never blocks the timer behind it. With the wrist down (`isLuminanceReduced`) the same
/// state renders as the always-on layouts: numbers only, no buttons.
struct ActiveWorkoutView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    /// Where VoiceOver focus goes back to once the record card has had its say.
    @AccessibilityFocusState private var contentFocused: Bool

    private var alwaysOn: Bool { isLuminanceReduced || WatchLaunchFlags.forcesAlwaysOn }

    var body: some View {
        @Bindable var store = store
        ZStack {
            Group {
                if alwaysOn {
                    AlwaysOnView()
                } else if let session = store.session, session.isResting,
                          session.restTotal > InlineRestView.maxInlineSeconds {
                    FullScreenRestView()
                } else {
                    pages
                }
            }
            .accessibilityFocused($contentFocused)
            .accessibilityHidden(store.recordCard != nil)
            if let card = store.recordCard {
                RecordCardView(card: card)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.recordCard?.id)
        .onChange(of: store.recordCard?.id) { previous, current in
            // The card took focus and announced once; hand focus back where it was.
            if previous != nil, current == nil { contentFocused = true }
        }
    }

    private var pages: some View {
        @Bindable var store = store
        return TabView(selection: $store.pageIndex) {
            if let session = store.session {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, entry in
                    ExercisePage(entry: entry).tag(index)
                }
                FinishPage().tag(session.exercises.count)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .top)
    }
}

/// The page after the last exercise: elapsed time and sets so far, Finish, Discard.
struct FinishPage: View {
    @Environment(WatchStore.self) private var store
    @State private var confirmDiscard = false

    var body: some View {
        let session = store.session
        VStack(spacing: 8) {
            SafeBandText(text: session?.title ?? "Workout", font: WatchFont.title, color: WatchColor.ink)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(WorkoutSession.clock(session?.elapsedSeconds(at: context.date) ?? 0))
                    .font(WatchFont.value(34, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
            }
            Text("\(session?.setsDone ?? 0) of \(session?.setsTotal ?? 0) sets")
                .font(WatchFont.body)
                .foregroundStyle(WatchColor.inkSecondary)
            Spacer()
            CapsuleButton(title: "Finish", tint: WatchColor.commit) { store.finish() }
            Button("Discard") { confirmDiscard = true }
                .font(WatchFont.body)
                .foregroundStyle(WatchColor.inkSecondary)
                .buttonStyle(.plain)
                .frame(height: WatchMetric.safeBand)
        }
        .padding(.horizontal, WatchMetric.gutter)
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard) {
            Button("Discard workout", role: .destructive) { store.discard() }
        }
    }
}
