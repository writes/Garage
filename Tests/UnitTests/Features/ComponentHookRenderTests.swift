import SwiftUI
import Testing
@testable import Garage

/// Proves the newly consumed component hooks reach PIXELS, which no value assertion can: deleting
/// the stroke from `CardModifier` or `PrimaryButton` leaves every seam test in
/// `ComponentHookRoutingTests` passing, and only a rasterized card can tell the difference.
///
/// Each test asserts BOTH directions — Underhood paints the hook, control paints nothing — so it is
/// simultaneously the consumption proof and the control-stability proof for that hook.
///
/// Serialized, and every body is synchronous: `DesignPackStore.shared` is process-wide state and
/// these tests deliberately drive it.
@MainActor
@Suite(.serialized)
struct ComponentHookRenderTests {
    private static let size = CGSize(width: 120, height: 80)

    /// Sampled well below the 18pt top-right chamfer and away from every corner, so the only thing
    /// that can be painted on the left edge is the hairline itself.
    private static let edge = (x: 0, y: 60)
    private static let interior = (x: 60, y: 60)

    private func card(_ pack: DesignPack) -> [UInt8]? {
        DesignPackStore.shared.apply(pack)
        return RenderProbe.pixels(of: Color.clear.garageCard(), size: Self.size)
    }

    /// The concept separates panels with a `--line` hairline instead of with elevation, so the card
    /// edge must differ from the card's own fill — and under control it must NOT, because control's
    /// zero-width stroke is the entire reason the consumer needs no `if`.
    @Test func theCardHairlineIsPaintedInUnderhoodAndNotInControl() {
        defer { DesignPackStore.shared.apply(arm: .control) }
        let width = Int(Self.size.width)

        guard let underhood = card(.variantA) else {
            Issue.record("the renderer produced no image for the Underhood card")
            return
        }
        let underhoodEdge = RenderProbe.pixel(underhood, width: width, column: Self.edge.x, row: Self.edge.y)
        let underhoodFill = RenderProbe.pixel(underhood, width: width, column: Self.interior.x, row: Self.interior.y)
        // Measured 11 (edge [31,37,44] over fill [20,27,35] — the ink hairline at the half of the
        // 1pt stroke that survives the clip). 8 leaves room for a rasterizer nudge without letting
        // the antialiasing floor below through.
        #expect(
            RenderProbe.distance(underhoodEdge, underhoodFill) >= 8,
            "Underhood's card hairline is not painted: edge \(underhoodEdge) vs fill \(underhoodFill)"
        )

        guard let control = card(.control) else {
            Issue.record("the renderer produced no image for the control card")
            return
        }
        let controlEdge = RenderProbe.pixel(control, width: width, column: Self.edge.x, row: Self.edge.y)
        let controlFill = RenderProbe.pixel(control, width: width, column: Self.interior.x, row: Self.interior.y)
        // 1, not 0: that is the rasterizer antialiasing the rounded clip against the edge of the
        // image, and it is what control measured BEFORE this wave wired the stroke. A 1pt hairline
        // at the pack's 10% would land an order of magnitude above it, as the Underhood arm shows.
        #expect(
            RenderProbe.distance(controlEdge, controlFill) <= 1,
            "control's card grew a border: edge \(controlEdge) vs fill \(controlFill)"
        )
    }

    /// The chamfer is the concept's corner language, and it is only real if the top-right corner is
    /// actually CUT — i.e. the page shows through where control would have painted the card.
    @Test func theTopRightCornerIsCutAwayInUnderhoodOnly() {
        defer { DesignPackStore.shared.apply(arm: .control) }
        let width = Int(Self.size.width)
        // (112, 6) is 6pt clear of the chamfer's hypotenuse (y = x - 102 for an 18pt cut on a 120pt
        // card) and 3pt inside control's 16pt rounded corner — the one sample that separates the two
        // geometries rather than landing outside both.
        let corner = (x: 112, y: 6)

        guard let underhood = card(.variantA), let control = card(.control) else {
            Issue.record("the renderer produced no image")
            return
        }
        let cut = RenderProbe.pixel(underhood, width: width, column: corner.x, row: corner.y)
        let fill = RenderProbe.pixel(underhood, width: width, column: Self.interior.x, row: Self.interior.y)
        // Measured [0,0,0] against a [20,27,35] fill: nothing is drawn there at all, which is what
        // a CUT corner means — not a lighter shade of card.
        #expect(
            RenderProbe.distance(cut, fill) >= 8,
            "Underhood's top-right corner is not cut: corner \(cut) vs fill \(fill)"
        )

        let controlCorner = RenderProbe.pixel(control, width: width, column: corner.x, row: corner.y)
        let controlFill = RenderProbe.pixel(control, width: width, column: Self.interior.x, row: Self.interior.y)
        #expect(
            RenderProbe.distance(controlCorner, controlFill) == 0,
            "control's card lost its square corner: corner \(controlCorner) vs fill \(controlFill)"
        )
    }
}
