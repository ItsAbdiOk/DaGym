import Testing
import UIKit

@testable import DaGym

@Suite("PhotoProcessor")
struct PhotoProcessorTests {
    /// A solid-color image of the given size, for deterministic downscale assertions.
    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test("downscales a large landscape image so the long edge is 1600")
    func downscalesLargeLandscape() throws {
        let image = makeImage(width: 4000, height: 3000)
        let processed = try #require(PhotoProcessor.process(image))
        #expect(processed.imageSize.width == PhotoProcessor.storageLongEdge)
        #expect(abs(processed.imageSize.height - 1200) < 1)
    }

    @Test("downscales a large portrait image so the long edge is 1600")
    func downscalesLargePortrait() throws {
        let image = makeImage(width: 1200, height: 1600)
        let processed = try #require(PhotoProcessor.process(image))
        #expect(processed.imageSize.height == PhotoProcessor.storageLongEdge)
        #expect(processed.imageSize.width < 1600)
    }

    @Test("never upscales an image already smaller than the target")
    func neverUpscales() throws {
        let image = makeImage(width: 400, height: 300)
        let processed = try #require(PhotoProcessor.process(image))
        #expect(processed.imageSize.width == 400)
        #expect(processed.imageSize.height == 300)
    }

    @Test("thumbnail long edge is 300")
    func thumbnailSize() throws {
        let image = makeImage(width: 1200, height: 1600)
        let processed = try #require(PhotoProcessor.process(image))
        #expect(processed.thumbnailSize.height == PhotoProcessor.thumbnailLongEdge)
        #expect(processed.thumbnailSize.width < PhotoProcessor.thumbnailLongEdge)
    }

    @Test("produces non-empty JPEG data for both sizes")
    func producesJPEGData() throws {
        let image = makeImage(width: 800, height: 800)
        let processed = try #require(PhotoProcessor.process(image))
        #expect(!processed.imageData.isEmpty)
        #expect(!processed.thumbnailData.isEmpty)
        #expect(processed.thumbnailData.count < processed.imageData.count)
    }
}
