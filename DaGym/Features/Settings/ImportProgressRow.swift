import SwiftUI

/// The "Importing… 1,240 of 3,000" line under the Settings import rows while `ImportActor` is
/// writing, with a working Cancel. Shown in place of the row's footnote so the card keeps its
/// shape; the row's own spinner stays.
struct ImportProgressRow: View {
    var title: String
    var progress: ImportProgress
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            HStack {
                Text(label)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.coral)
                    .buttonStyle(.plain)
            }
            ProgressView(value: progress.fraction)
                .tint(DGColor.coral)
                .accessibilityLabel(label)
        }
    }

    private var label: String {
        guard progress.total > 0 else { return "\(title)…" }
        return "\(title)… \(progress.done.formatted()) of \(progress.total.formatted())"
    }
}

/// Feeds `ImportActor`'s off-main progress callbacks to the main actor one at a time. The actor
/// calls `handler` from its own executor; the view reads `latest` on the main actor after each
/// hop, so `@State` is only ever written from the main actor.
@MainActor
final class ImportProgressRelay {
    private let stream: AsyncStream<ImportProgress>
    private let continuation: AsyncStream<ImportProgress>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: ImportProgress.self)
    }

    /// What the actor calls; safe from any thread.
    var handler: ImportActor.ProgressHandler {
        let continuation = continuation
        return { progress in continuation.yield(progress) }
    }

    /// Runs `apply` on the main actor for every update until `finish()`.
    func observe(_ apply: @escaping @MainActor (ImportProgress) -> Void) -> Task<Void, Never> {
        let stream = stream
        return Task { @MainActor in
            for await progress in stream { apply(progress) }
        }
    }

    func finish() { continuation.finish() }
}
