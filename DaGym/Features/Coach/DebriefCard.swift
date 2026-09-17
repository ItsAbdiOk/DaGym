import GymCore
import os
import SwiftUI
import Synchronization

/// Shared by the Coach feature's views and loaders.
let coachLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "coach")

/// The workout debrief on `WorkoutSummaryView`: a score out of ten and three short lists,
/// streamed in from `CoachLanguageModel.debrief(facts:)`. Skeleton rows while the first
/// snapshot loads; the rule debrief if the model fails or is rejected; hidden altogether when
/// even the rules have nothing cited to say. Every bullet on screen has passed
/// `DebriefValidator` — the card never shows a claim that doesn't cite a fact it was given.
struct DebriefCard: View {
    var facts: SessionSummaryFacts

    @Environment(CoachServices.self) private var coach
    @State private var debrief: SessionDebrief?
    @State private var isHidden = false
    /// Drives the skeleton's shimmer while the model writes.
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !isHidden {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                header
                if let debrief {
                    lists(debrief)
                } else {
                    skeleton
                }
            }
            .padding(DGSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dgTile(radius: 20, opacity: 0.66)
            .task { await load() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yID.debriefCard)
        }
    }

    /// Accent chat glyph, "Coach debrief", and the score as "8/10" once it's in.
    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "bubble.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DGColor.inkOnCoral)
                .frame(width: 28, height: 28)
                .background(DGColor.coral, in: Circle())
                .accessibilityHidden(true)
            Text("Coach debrief")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
            Spacer()
            if let score = debrief?.score {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DGColor.ink1)
                    Text("/10")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DGColor.ink3)
                }
                .monospacedDigit()
                .accessibilityLabel("Score \(score) out of 10")
            }
        }
    }

    private func lists(_ debrief: SessionDebrief) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // "Went well" carries the accent; the other two stay ink, as in the prototype.
            list("Went well", debrief.wentWell, tint: DGColor.coralText)
            list("Watch", debrief.watch, tint: DGColor.ink3)
            list("Try next", debrief.tryNext, tint: DGColor.ink3)
            Text(coach.isUsingLanguageModel
                 ? "Written on your iPhone from this session's numbers. Nothing is sent anywhere."
                 : "From the rule-based coach. Nothing is sent anywhere.")
                .font(.system(size: 11))
                .foregroundStyle(DGColor.ink4)
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ claims: [CoachClaim], tint: Color) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                ForEach(Array(claims.enumerated()), id: \.offset) { _, claim in
                    Text(claim.text)
                        .font(.system(size: 13))
                        .foregroundStyle(DGColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Three shimmering bars (full, 82 %, 64 % wide) while the first snapshot loads.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            ForEach([1.0, 0.82, 0.64], id: \.self) { fraction in
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DGColor.ink1.opacity(0.1))
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: 11)
            }
        }
        .opacity(shimmer ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: shimmer)
        // Reduce Motion: the bars sit still at the dimmed opacity rather than pulsing.
        .onAppear { shimmer = !reduceMotion }
        .accessibilityLabel("Writing the debrief")
    }

    /// Streams the model's debrief, repainting on every snapshot so the card fills in as the
    /// model writes; on any failure shows the rule debrief instead, and hides the card when
    /// even that has nothing to say (`DebriefValidator` returned nil).
    private func load() async {
        let result = await DebriefLoader.load(facts: facts, model: coach.model) { snapshot in
            debrief = snapshot
        }
        guard !Task.isCancelled else { return }
        debrief = result
        isHidden = result == nil
    }
}

/// The debrief's fallback ladder, off the view so it can be pinned in a test: the model's last
/// streamed snapshot — including a partial one when the stream then throws or has not finished
/// within `timeout` (a model that is warming up or throttled never throws — it just never
/// answers, and the skeleton would shimmer for good); the rule debrief when nothing streamed
/// at all; nil when even the rules have nothing cited to say. `onSnapshot` fires for every
/// snapshot as it arrives, on the main actor, so the card can show the model's work in
/// progress instead of a skeleton until the stream ends.
enum DebriefLoader {
    static let defaultTimeout: Duration = .seconds(8)

    static func load(
        facts: SessionSummaryFacts, model: any CoachLanguageModel, timeout: Duration = defaultTimeout,
        onSnapshot: @escaping @MainActor @Sendable (SessionDebrief) -> Void = { _ in }
    ) async -> SessionDebrief? {
        // Shared between the stream and the timeout task, so whichever finishes first can hand
        // back whatever had streamed by then.
        let latest = Mutex<SessionDebrief?>(nil)
        let streamed = await withTaskGroup(of: SessionDebrief?.self) { group in
            group.addTask {
                do {
                    for try await snapshot in model.debrief(facts: facts) {
                        latest.withLock { $0 = snapshot }
                        await onSnapshot(snapshot)
                    }
                } catch where !(error is CancellationError) {
                    // A stream that *failed* mid-way leaves a half-written list; the rules are
                    // always complete, so they win here. A timeout (below) keeps the partial —
                    // a slow model's first bullets are still better than none.
                    coachLogger.error("Debrief stream failed: \(error, privacy: .public)")
                    return nil
                } catch {
                    // Cancelled by the timeout below or by the card leaving the screen.
                }
                return latest.withLock { $0 }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return latest.withLock { $0 }
            }
            let first = await group.next().flatMap { $0 }
            group.cancelAll()
            return first
        }
        if let streamed { return streamed }
        return DebriefValidator.validate(DebriefRules.debrief(from: facts), facts: facts)
    }
}
