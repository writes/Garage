import UIKit

/// Downsamples a picked photo before it ever reaches Storage — external audit finding ("photo
/// downsampling unmeasured"): this makes the bound explicit, fixed, and unit-testable instead of
/// shipping the original multi-MB camera capture. Pure/stateless: no Firebase, no view-layer
/// dependency.
enum AttachmentImageProcessor {
    /// Longest edge, in points, after downsampling.
    static let maxDimension: CGFloat = 2_048
    static let jpegQuality: CGFloat = 0.8

    /// Nil if `data` isn't a decodable image, or JPEG encoding fails. Images already at or under
    /// the bound are re-encoded (not just passed through) so every attachment gets a consistent
    /// compression pass regardless of source format (HEIC, PNG, etc.).
    static func downsampledJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return resized(image, maxDimension: maxDimension).jpegData(compressionQuality: jpegQuality)
    }

    /// Scales `image` down so its longest edge is at most `maxDimension`, preserving aspect
    /// ratio. Returns `image` unchanged if it's already within bounds (never upscales).
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > 0 else { return image }
        let needsResize = longestEdge > maxDimension
        // Re-render even within bounds when the backing scale isn't 1: jpegData encodes
        // PIXELS (points x scale), so a 3x 200pt image would upload as 600px.
        guard needsResize || image.scale != 1 else { return image }
        let scale = needsResize ? maxDimension / longestEdge : 1
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Scale 1, not the device's: the default renderer format multiplies by screen scale
        // (3x on modern iPhones), which would upload a 6144px image for a "2048pt" bound.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
