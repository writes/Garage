import SwiftUI
import Testing
import UIKit
@testable import Garage

/// The parity contract's contrast lane for variant_a (master plan §6.3: "Underhood × all 4 accents
/// × component states").
///
/// `ColorContrastTests` measures the ASSET catalog, which is control's palette; Underhood's palette
/// is srgb literals inside a pack, so nothing in that file can see it. Every ratio here is computed
/// from the pack's own tokens — not from restated hexes — so a token edit is measured, not assumed,
/// and the four Pro accents are resolved through `AccentScheme` in the DARK appearance this arm
/// commits to, because an explicitly-picked accent still wins inside the pack.
@MainActor
struct UnderhoodContrastTests {
    /// WCAG 2.1: 4.5:1 for normal text, 3:1 for large text and non-text UI components.
    private static let textMinimum = 4.5
    private static let nonTextMinimum = 3.0

    private let pack = DesignPack.variantA

    // MARK: - Measurement

    private struct Channels {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    /// The pack's tokens are `.srgb` literals by construction; an `.asset` would mean a colorset
    /// leaked into a world that has no light variant, which is itself a failure.
    private func channels(_ token: DesignColor, _ role: String) -> Channels? {
        guard case .srgb(let red, let green, let blue, let opacity) = token else {
            Issue.record("Underhood's \(role) is an asset colorset, not an srgb literal")
            return nil
        }
        return Channels(red: red, green: green, blue: blue, alpha: opacity)
    }

    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Channels(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }

    /// The four Pro accents as they resolve in THIS arm's appearance. Driven off `AccentScheme` so
    /// a new scheme, or a repainted tint, is covered without this file being edited.
    private func tint(_ scheme: AccentScheme) -> Channels {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        return channels(UIColor(scheme.tint).resolvedColor(with: dark))
    }

    /// WCAG relative luminance.
    private func luminance(_ color: Channels) -> Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(color.red)
            + 0.7152 * linearize(color.green)
            + 0.0722 * linearize(color.blue)
    }

    private func contrast(_ first: Channels, _ second: Channels) -> Double {
        let left = luminance(first)
        let right = luminance(second)
        return (max(left, right) + 0.05) / (min(left, right) + 0.05)
    }

    /// Composites `foreground` at `alpha` over `background` — the BadgeView pattern, where a colour
    /// is drawn as text on a faint tint of itself.
    private func composite(_ foreground: Channels, over background: Channels, alpha: Double) -> Channels {
        Channels(
            red: foreground.red * alpha + background.red * (1 - alpha),
            green: foreground.green * alpha + background.green * (1 - alpha),
            blue: foreground.blue * alpha + background.blue * (1 - alpha),
            alpha: 1
        )
    }

    private func check(
        _ foreground: DesignColor,
        _ foregroundRole: String,
        on background: DesignColor,
        _ backgroundRole: String,
        minimum: Double
    ) {
        guard let front = channels(foreground, foregroundRole),
              let back = channels(background, backgroundRole) else { return }
        let ratio = contrast(front, back)
        #expect(
            ratio >= minimum,
            "\(foregroundRole) on \(backgroundRole) is \(String(format: "%.2f", ratio)):1, needs \(minimum):1"
        )
    }

    // MARK: - Body text on the two page surfaces

    @Test func bodyTextClearsAAOnBothUnderhoodSurfaces() {
        check(pack.colors.textPrimary, "ink", on: pack.colors.background, "bg", minimum: Self.textMinimum)
        check(pack.colors.textPrimary, "ink", on: pack.colors.surface, "surface", minimum: Self.textMinimum)
        check(pack.colors.textSecondary, "muted", on: pack.colors.background, "bg", minimum: Self.textMinimum)
        check(pack.colors.textSecondary, "muted", on: pack.colors.surface, "surface", minimum: Self.textMinimum)
    }

    /// The status colours are drawn as text and icons straight onto both surfaces.
    @Test func statusTextClearsAAOnBothUnderhoodSurfaces() {
        let roles = [
            (pack.colors.success, "ok"), (pack.colors.error, "bad"), (pack.colors.warning, "warning")
        ]
        for (token, role) in roles {
            check(token, role, on: pack.colors.background, "bg", minimum: Self.textMinimum)
            check(token, role, on: pack.colors.surface, "surface", minimum: Self.textMinimum)
        }
    }

    /// Elevation has to read without a shadow: the hairline does most of the work, but the card
    /// still has to be a different colour from the page behind it.
    @Test func theSurfaceSeparatesFromTheBackground() {
        guard let surface = channels(pack.colors.surface, "surface"),
              let background = channels(pack.colors.background, "bg") else { return }
        #expect(contrast(surface, background) > 1.05, "cards must be visible against the page")
    }

    // MARK: - onPrimary over every accent this arm can render

    /// The pack's OWN default fill — the amber a user with no accent choice on record sees.
    @Test func onPrimaryClearsAAOnTheAmberDefault() {
        check(pack.colors.onPrimary, "onPrimary", on: pack.colors.accentDefault, "amber", minimum: Self.textMinimum)
    }

    /// And over all four Pro accents, because an explicit pick beats the pack default inside this
    /// arm — so the near-black `onPrimary` has to survive every one of them, not just the amber.
    @Test func onPrimaryClearsAAOnEveryProAccentInThisArm() {
        guard let onPrimary = channels(pack.colors.onPrimary, "onPrimary") else { return }
        for scheme in AccentScheme.allCases {
            let ratio = contrast(onPrimary, tint(scheme))
            #expect(
                ratio >= Self.textMinimum,
                "onPrimary on \(scheme.rawValue) is \(String(format: "%.2f", ratio)):1"
            )
        }
    }

    /// A filled control also has to be distinguishable from the page behind it — the 3:1 non-text
    /// floor, applied to the amber default and to every Pro accent in this world.
    @Test func everyAccentFillSeparatesFromTheUnderhoodPage() {
        guard let background = channels(pack.colors.background, "bg") else { return }
        check(pack.colors.accentDefault, "amber", on: pack.colors.background, "bg", minimum: Self.nonTextMinimum)
        for scheme in AccentScheme.allCases {
            let ratio = contrast(tint(scheme), background)
            #expect(
                ratio >= Self.nonTextMinimum,
                "\(scheme.rawValue) fill on bg is \(String(format: "%.2f", ratio)):1"
            )
        }
    }

    /// Guards the resolution itself: if `UIColor(_:).resolvedColor(with:)` ever stopped following
    /// the appearance, every ratio above would silently be measuring the LIGHT tints against a dark
    /// page and passing for the wrong reason.
    @Test func theProAccentsAreBeingResolvedInTheDarkAppearance() {
        let light = channels(UIColor(AccentScheme.marine.tint)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        let dark = tint(.marine)
        #expect(luminance(dark) > luminance(light), "the dark tint is the lightened one")
    }

    // MARK: - The one known miss, pinned rather than hidden

    /// `BadgeView` draws caption text on a 12% tint of itself — structurally the lowest-contrast
    /// surface in the app. Two of the three status colours clear AA there; `error` does not, at
    /// 4.17:1 against the 4.5:1 text floor.
    ///
    /// It is NOT adjusted here: `--bad:#E4572E` is one of the concept's anchor colours, the wave
    /// spec forbids moving those, and the anchor passes everywhere it is measured as text
    /// (5.11:1 on bg, 4.71:1 on surface — see `statusTextClearsAAOnBothUnderhoodSurfaces`). It
    /// clears the 3:1 non-text floor, so the pin below asserts that floor and records the exact
    /// number: an operator/design decision to move the anchor, or to give badges a solid fill in
    /// this world, re-opens HERE and fails loudly if the ratio drifts either way.
    @Test func theBadgeCompositeIsPinnedIncludingErrorsKnownAAMiss() {
        guard let surface = channels(pack.colors.surface, "surface") else { return }
        // `clearsAA` is the pin: two of the three do, `bad` does not, and either changing sides is
        // the drift this test exists to catch.
        let cases: [(role: String, clearsAA: Bool)] = [
            ("ok", true), ("warning", true), ("bad", false)
        ]
        let tokens = [
            "ok": pack.colors.success, "warning": pack.colors.warning, "bad": pack.colors.error
        ]
        for (role, clearsAA) in cases {
            guard let token = tokens[role], let color = channels(token, role) else { continue }
            let ratio = contrast(color, composite(color, over: surface, alpha: 0.12))
            #expect(
                ratio >= Self.nonTextMinimum,
                "\(role) badge text is \(String(format: "%.2f", ratio)):1, below even the non-text floor"
            )
            if clearsAA {
                #expect(
                    ratio >= Self.textMinimum,
                    "\(role) badge text is \(String(format: "%.2f", ratio)):1 — its AA status changed"
                )
            } else {
                // A KNOWN ISSUE, not a passing contract (cross-check finding): the AA expectation
                // stands and is recorded as expected-to-fail. If the anchor moves or badges gain a
                // solid fill and `bad` reaches AA, withKnownIssue flips this test red — the same
                // loud drift-trip, with the miss accounted honestly in every test run.
                let miss = String(format: "%.2f", ratio)
                withKnownIssue("\(role) badge misses AA at \(miss):1 — U2' decision owed") {
                    #expect(ratio >= Self.textMinimum)
                }
            }
        }
    }
}
