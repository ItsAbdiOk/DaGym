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
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    .strokeBorder(DGColor.hairline, lineWidth: 1)
            }
            .task { await load() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yID.debriefCard)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Debrief").dgLabel()
            Spacer()
            if let score = debrief?.score {
                Text("\(score)/10")
                    .font(DGFont.title3)
                    .foregroundStyle(coach.isUsingLanguageModel ? DGColor.aiVioletText : DGColor.ink1)
                    .accessibilityLabel("Score \(score) out of 10")
            }
        }
    }

    private func lists(_ debrief: SessionDebrief) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            list("Went well", debrief.wentWell)
            list("Watch", debrief.watch)
            list("Try next", debrief.tryNext)
            Text(coach.isUsingLanguageModel
                 ? "Written on your iPhone from this session's numbers. Nothing is sent anywhere."
                 : "From the rule-based coach. Nothing is sent anywhere.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ claims: [CoachClaim]) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text(title)
                    .font(DGFont.condensedLabel(12))
                    .foregroundStyle(DGColor.ink3)
                ForEach(Array(claims.enumerated()), id: \.offset) { _, claim in
                    Text("• \(claim.text)")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DGColor.surface3)
                    .frame(maxWidth: index == 2 ? 180 : .infinity)
                    .frame(height: 14)
            }
        }
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
