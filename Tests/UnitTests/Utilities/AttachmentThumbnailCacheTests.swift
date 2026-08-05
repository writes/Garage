import CoreGraphics
import Testing
@testable import Garage

@MainActor
struct AttachmentThumbnailCacheTests {
    private static func makeImage(side: Int = 4) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }

    @Test func missReturnsNilForAnUnknownPath() {
        let cache = AttachmentThumbnailCache()
        #expect(cache.image(forPath: "users/u/entries/e/receipt.jpg", maxPixelSize: 132) == nil)
    }

    @Test func storedThumbnailIsReturnedForTheSamePathAndSize() throws {
        let cache = AttachmentThumbnailCache()
        let image = try #require(Self.makeImage())
        cache.store(image, forPath: "a/b/c.jpg", maxPixelSize: 132)
        #expect(cache.image(forPath: "a/b/c.jpg", maxPixelSize: 132) === image)
    }

    /// The bound is points x displayScale, so the same attachment is a genuinely different image on
    /// a 2x and a 3x screen. A size-blind key would hand a 2x render to a 3x row, rendering soft.
    @Test func sizeIsPartOfTheKey() throws {
        let cache = AttachmentThumbnailCache()
        let image = try #require(Self.makeImage())
        cache.store(image, forPath: "a/b/c.jpg", maxPixelSize: 88)
        #expect(cache.image(forPath: "a/b/c.jpg", maxPixelSize: 88) != nil)
        #expect(cache.image(forPath: "a/b/c.jpg", maxPixelSize: 132) == nil)
    }

    @Test func differentPathsDoNotShareAnEntry() throws {
        let cache = AttachmentThumbnailCache()
        let first = try #require(Self.makeImage(side: 4))
        let second = try #require(Self.makeImage(side: 8))
        cache.store(first, forPath: "a/one.jpg", maxPixelSize: 132)
        cache.store(second, forPath: "a/two.jpg", maxPixelSize: 132)
        #expect(cache.image(forPath: "a/one.jpg", maxPixelSize: 132) === first)
        #expect(cache.image(forPath: "a/two.jpg", maxPixelSize: 132) === second)
    }

    /// A path that ends where another's size suffix begins must not read the other's entry.
    @Test func pathAndSizeSegmentsCannotBeConfusedForEachOther() throws {
        let cache = AttachmentThumbnailCache()
        let image = try #require(Self.makeImage())
        cache.store(image, forPath: "a/b", maxPixelSize: 132)
        #expect(cache.image(forPath: "a", maxPixelSize: 132) == nil)
    }
}
