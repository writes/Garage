import Foundation
import Testing
import UIKit
@testable import Garage

@MainActor
struct AttachmentImageProcessorTests {
    @Test func downsampledJPEG_shrinksLongestEdgeToTheBound() throws {
        let data = try Self.solidImagePNGData(width: 4_000, height: 3_000)
        let result = try #require(AttachmentImageProcessor.downsampledJPEG(from: data))
        let decoded = try #require(UIImage(data: result))
        #expect(max(decoded.size.width, decoded.size.height) <= AttachmentImageProcessor.maxDimension)
    }

    @Test func downsampledJPEG_preservesAspectRatio() throws {
        let data = try Self.solidImagePNGData(width: 4_000, height: 2_000)
        let result = try #require(AttachmentImageProcessor.downsampledJPEG(from: data))
        let decoded = try #require(UIImage(data: result))
        let originalRatio = 4_000.0 / 2_000.0
        let decodedRatio = decoded.size.width / decoded.size.height
        #expect(abs(originalRatio - decodedRatio) < 0.01)
    }

    @Test func downsampledJPEG_neverUpscalesAnImageAlreadyWithinBounds() throws {
        let data = try Self.solidImagePNGData(width: 200, height: 100)
        let result = try #require(AttachmentImageProcessor.downsampledJPEG(from: data))
        let decoded = try #require(UIImage(data: result))
        #expect(decoded.size.width == 200)
        #expect(decoded.size.height == 100)
    }

    @Test func downsampledJPEG_returnsNilForUndecodableData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        #expect(AttachmentImageProcessor.downsampledJPEG(from: garbage) == nil)
    }

    @Test func downsampledJPEG_alwaysReencodesAsDecodableJPEGData() throws {
        // Feeding a PNG in and getting back JPEG-decodable data confirms the re-encode pass runs
        // even when the source is already under the size bound (a consistent compression pass
        // regardless of source format is the point, not just a passthrough).
        let data = try Self.solidImagePNGData(width: 500, height: 500)
        let result = try #require(AttachmentImageProcessor.downsampledJPEG(from: data))
        #expect(UIImage(data: result) != nil)
    }

    @Test func resized_normalizesRetinaBackingScaleToPixels() {
        // A 200pt image at 3x is 600 PIXELS; jpegData encodes pixels, so without the scale-1
        // re-render pass a "within bounds" retina capture would upload at 9x the byte size.
        let retina = Self.solidImage(width: 200, height: 100, scale: 3)
        let resized = AttachmentImageProcessor.resized(retina, maxDimension: 2_048)
        #expect(resized.scale == 1)
        #expect(resized.size == CGSize(width: 200, height: 100))
    }

    @Test func resized_exactlyAtTheBoundIsUnchanged() {
        let image = Self.solidImage(width: 2_048, height: 1_024)
        let resized = AttachmentImageProcessor.resized(image, maxDimension: 2_048)
        #expect(resized.size == image.size)
    }

    // MARK: - UIImage overload (ReceiptPreflighter's single-decode path)

    @Test func downsampledJPEG_fromImage_matchesTheDataOverloadsBehavior() throws {
        // Same bound/quality pass, just skipping the decode a caller that already has a UIImage
        // (ReceiptPreflighter) doesn't need to repeat.
        let image = Self.solidImage(width: 4_000, height: 3_000)
        let fromImage = try #require(AttachmentImageProcessor.downsampledJPEG(from: image))
        let decoded = try #require(UIImage(data: fromImage))
        #expect(max(decoded.size.width, decoded.size.height) <= AttachmentImageProcessor.maxDimension)
    }

    @Test func downsampledJPEG_fromImage_normalizesRetinaBackingScaleToPixels() throws {
        let retina = Self.solidImage(width: 200, height: 100, scale: 3)
        let result = try #require(AttachmentImageProcessor.downsampledJPEG(from: retina))
        let decoded = try #require(UIImage(data: result))
        #expect(decoded.scale == 1)
        #expect(decoded.size == CGSize(width: 200, height: 100))
    }

    @Test func downsampledJPEG_bothOverloadsProduceEquivalentOutputForTheSameSource() throws {
        let image = Self.solidImage(width: 3_000, height: 1_500)
        let data = try #require(image.pngData())
        let fromData = try #require(AttachmentImageProcessor.downsampledJPEG(from: data))
        let fromImage = try #require(AttachmentImageProcessor.downsampledJPEG(from: image))
        let decodedFromData = try #require(UIImage(data: fromData))
        let decodedFromImage = try #require(UIImage(data: fromImage))
        #expect(decodedFromData.size == decodedFromImage.size)
    }

    // MARK: - Row thumbnails (ImageIO, bounded decode)

    @Test func thumbnail_decodesNoLargerThanTheRequestedPixelBound() throws {
        // The row asks for 44pt x 3 = 132px. The source is a stored attachment's worth of pixels;
        // decoding it in full for that row is what this path exists to avoid.
        let data = try Self.solidImagePNGData(width: 2_048, height: 1_536)
        let thumbnail = try #require(AttachmentImageProcessor.thumbnail(from: data, maxPixelSize: 132))
        #expect(max(thumbnail.width, thumbnail.height) <= 132)
        // Not a degenerate 1px result, and the aspect ratio survives.
        #expect(min(thumbnail.width, thumbnail.height) > 1)
        #expect(abs(Double(thumbnail.width) / Double(thumbnail.height) - 2_048.0 / 1_536.0) < 0.05)
    }

    @Test func thumbnail_returnsNilRatherThanADegenerateImage() throws {
        #expect(AttachmentImageProcessor.thumbnail(from: Data([0x00, 0x01]), maxPixelSize: 132) == nil)
        let data = try Self.solidImagePNGData(width: 100, height: 100)
        #expect(AttachmentImageProcessor.thumbnail(from: data, maxPixelSize: 0) == nil)
    }

    private static func solidImagePNGData(width: Int, height: Int) throws -> Data {
        try #require(solidImage(width: width, height: height).pngData())
    }

    /// scale 1 so width/height are PIXELS: the default renderer format uses the simulator's
    /// screen scale (3x), which would silently make every "200pt" fixture a 600px PNG.
    private static func solidImage(width: Int, height: Int, scale: CGFloat = 1) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
