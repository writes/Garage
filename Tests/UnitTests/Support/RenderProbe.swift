import SwiftUI
import UIKit

/// Rasterizes a view and reads individual pixels back.
///
/// A pack hook is only really "consumed" if it reaches the screen, and a value test on the style
/// struct cannot see that: delete the stroke from `CardModifier` and every seam assertion still
/// passes. So the newly consumed component hooks are proven HERE, against pixels — the same thing
/// the master plan's Phase-3 snapshot lane will do at whole-screen scale, borrowed early for the
/// two hooks wave U1′ wires.
@MainActor
enum RenderProbe {
    /// Straight sRGB, non-premultiplied, one byte per channel, so a sampled pixel is comparable to
    /// the literal that produced it without undoing any alpha maths.
    static func pixels(of view: some View, size: CGSize) -> [UInt8]? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        // 1 point == 1 pixel: the probe samples geometry it computed in points.
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }

        let width = Int(size.width)
        let height = Int(size.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(origin: .zero, size: size))
            return true
        }
        return drawn ? buffer : nil
    }

    /// The RGB of one pixel, in the same top-left origin the view was laid out in.
    static func pixel(_ buffer: [UInt8], width: Int, column: Int, row: Int) -> [Int] {
        let offset = (row * width + column) * 4
        guard offset + 2 < buffer.count else { return [] }
        return [Int(buffer[offset]), Int(buffer[offset + 1]), Int(buffer[offset + 2])]
    }

    /// The largest per-channel difference between two sampled pixels. Compared as a distance rather
    /// than for equality because a hairline is antialiased: what matters is that something was
    /// painted there, not the exact blend the rasterizer chose.
    static func distance(_ first: [Int], _ second: [Int]) -> Int {
        guard first.count == 3, second.count == 3 else { return -1 }
        return zip(first, second).map { abs($0 - $1) }.max() ?? 0
    }
}
