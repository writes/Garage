import CoreGraphics
import Foundation

/// Memoizes decoded attachment thumbnails across row lifetimes.
///
/// `URLCache` already spares the network hop when a scrolled-away row re-runs its `.task`, but not
/// the ImageIO decode — and the decode is the expensive half. Row state is recreated every time the
/// row leaves and re-enters the list, so scrolling a long entry's attachments re-decoded every
/// thumbnail on every pass.
///
/// Keyed by path AND pixel size: the bound is points x displayScale, so the same attachment is a
/// different image on a 2x and a 3x screen, and serving one for the other renders soft.
///
/// `NSCache`, not a dictionary: it evicts under memory pressure by itself, which is the whole
/// reason a thumbnail cache is safe to keep around at all.
@MainActor
final class AttachmentThumbnailCache {
    static let shared = AttachmentThumbnailCache()

    private let storage = NSCache<NSString, CGImage>()

    /// `countLimit` is injectable purely so the eviction contract is testable; callers use `shared`.
    init(countLimit: Int = 120) {
        storage.countLimit = countLimit
    }

    func image(forPath path: String, maxPixelSize: Int) -> CGImage? {
        storage.object(forKey: Self.key(path: path, maxPixelSize: maxPixelSize))
    }

    func store(_ image: CGImage, forPath path: String, maxPixelSize: Int) {
        storage.setObject(image, forKey: Self.key(path: path, maxPixelSize: maxPixelSize))
    }

    /// `#` cannot appear in a Storage object path, so it can't be produced by a path alone —
    /// otherwise "a/b" at size 44 and "a" at size "b#44" would collide.
    private static func key(path: String, maxPixelSize: Int) -> NSString {
        "\(path)#\(maxPixelSize)" as NSString
    }
}
