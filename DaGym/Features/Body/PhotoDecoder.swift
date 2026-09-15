import UIKit

/// Decodes progress-photo bytes into display-ready `UIImage`s off the main thread. `UIImage(data:)`
/// is lazy — the JPEG is actually decoded on first draw — so a fresh `UIImage` inside `body`
/// means a full decode per render. `preparingForDisplay()` forces that decode once, on a
/// background task, and the caller keeps the result in `@State`.
enum PhotoDecoder {
    /// Synchronous variant for callers already off the main thread (and for tests).
    nonisolated static func decodeNow(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingForDisplay() ?? image
    }

    /// Decodes `data` on a detached task; nil for bytes that aren't an image.
    static func decodeForDisplay(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) { decodeNow(data) }.value
    }

    /// Forces a decode of an already-constructed image (a camera capture) off the main thread.
    static func prepareForDisplay(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) { image.preparingForDisplay() ?? image }.value
    }
}
