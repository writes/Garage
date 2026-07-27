import Testing
import UIKit
@testable import Garage

/// Computes WCAG contrast from the COMPILED asset catalog, in both appearances.
///
/// This exists because contrast is invisible to every other check in the pipeline: the colours
/// compile, the app builds, the UI journeys pass, and text can still be unreadable. `Accent`
/// shipped at 2.74:1 and `Warning` at 2.37:1 — below even the 3:1 non-text floor — for as long as
/// the palette existed. Resolving the real `UIColor` rather than asserting on hex literals means a
/// change made in Xcode's asset editor is caught too.
@MainActor
struct ColorContrastTests {
    /// WCAG 2.1: 4.5:1 for normal text, 3:1 for large text and non-text UI components.
    private static let textMinimum = 4.5
    private static let nonTextMinimum = 3.0

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        init(_ color: UIColor) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    private func resolve(_ name: String, dark: Bool) -> UIColor? {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return UIColor(named: name, in: .main, compatibleWith: traits)
    }

    /// WCAG relative luminance.
    private func luminance(_ color: UIColor) -> Double {
        let channels = Channels(color)
        func linearize(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(channels.red)
            + 0.7152 * linearize(channels.green)
            + 0.0722 * linearize(channels.blue)
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        let left = luminance(first)
        let right = luminance(second)
        return (max(left, right) + 0.05) / (min(left, right) + 0.05)
    }

    /// Composites `foreground` at `alpha` over `background` — the badge pattern, where a colour is
    /// drawn as text on a faint tint of itself.
    private func composite(
        _ foreground: UIColor,
        over background: UIColor,
        alpha: CGFloat
    ) -> UIColor {
        let front = Channels(foreground)
        let back = Channels(background)
        return UIColor(
            red: front.red * alpha + back.red * (1 - alpha),
            green: front.green * alpha + back.green * (1 - alpha),
            blue: front.blue * alpha + back.blue * (1 - alpha),
            alpha: 1
        )
    }

    private func ratioText(_ ratio: Double) -> String {
        String(format: "%.2f", ratio)
    }

    private func check(
        _ token: String,
        against surface: String,
        dark: Bool,
        minimum: Double,
        label: String
    ) {
        guard let foreground = resolve(token, dark: dark),
              let background = resolve(surface, dark: dark) else {
            Issue.record("missing colorset: \(token) or \(surface)")
            return
        }
        let ratio = contrast(foreground, background)
        let mode = dark ? "dark" : "light"
        #expect(
            ratio >= minimum,
            "\(token) on \(surface) [\(mode)] is \(ratioText(ratio)):1, needs \(minimum):1 — \(label)"
        )
    }

    // MARK: - Body text

    @Test(arguments: [false, true])
    func textPrimary_clearsAAOnBothSurfaces(dark: Bool) {
        check("TextPrimary", against: "Background", dark: dark, minimum: Self.textMinimum, label: "body text")
        check("TextPrimary", against: "Surface", dark: dark, minimum: Self.textMinimum, label: "body on cards")
    }

    @Test(arguments: [false, true])
    func textSecondary_clearsAAOnBothSurfaces(dark: Bool) {
        check("TextSecondary", against: "Background", dark: dark, minimum: Self.textMinimum, label: "secondary")
        check("TextSecondary", against: "Surface", dark: dark, minimum: Self.textMinimum, label: "secondary on cards")
    }

    // MARK: - Semantic accents

    /// Drawn as status text and icons directly on the background. `Accent` and `Warning` both
    /// failed here until 2026-07-27.
    @Test(arguments: [false, true])
    func semanticColors_clearAAAsTextOnBackground(dark: Bool) {
        for token in ["Accent", "Warning", "Error", "Success"] {
            check(token, against: "Background", dark: dark, minimum: Self.textMinimum, label: "status text")
        }
    }

    /// The BadgeView pattern: caption text on a 12% tint of itself. Structurally the lowest
    /// contrast surface in the app, and the one that exposed the original failures.
    @Test(arguments: [false, true])
    func semanticColors_clearAAAsBadgeText(dark: Bool) {
        guard let surface = resolve("Surface", dark: dark) else {
            Issue.record("missing Surface colorset")
            return
        }
        let mode = dark ? "dark" : "light"
        for token in ["Accent", "Warning", "Error", "Success"] {
            guard let color = resolve(token, dark: dark) else {
                Issue.record("missing colorset: \(token)")
                continue
            }
            let tint = composite(color, over: surface, alpha: 0.12)
            let ratio = contrast(color, tint)
            #expect(
                ratio >= Self.textMinimum,
                "\(token) badge text [\(mode)] is \(ratioText(ratio)):1, needs \(Self.textMinimum):1"
            )
        }
    }

    // MARK: - Accent fills

    /// Every Pro accent tint is used as a filled button surface with `OnPrimary` on top.
    @Test(arguments: [false, true])
    func onPrimary_clearsAAOnEveryAccentTint(dark: Bool) {
        guard let onPrimary = resolve("OnPrimary", dark: dark) else {
            Issue.record("missing OnPrimary colorset")
            return
        }
        let mode = dark ? "dark" : "light"
        for tint in ["BrandPrimary", "AccentGraphite", "AccentMarine", "AccentPlum"] {
            guard let fill = resolve(tint, dark: dark) else {
                Issue.record("missing colorset: \(tint)")
                continue
            }
            let ratio = contrast(onPrimary, fill)
            #expect(
                ratio >= Self.textMinimum,
                "OnPrimary on \(tint) [\(mode)] is \(ratioText(ratio)):1"
            )
        }
    }

    /// A filled control must also be distinguishable from the background behind it.
    @Test(arguments: [false, true])
    func accentFills_separateFromBackground(dark: Bool) {
        for tint in ["BrandPrimary", "AccentGraphite", "AccentMarine", "AccentPlum"] {
            check(tint, against: "Background", dark: dark, minimum: Self.nonTextMinimum, label: "fill vs page")
        }
    }

    /// Elevation must read in both appearances — in dark mode Surface is LIGHTER than Background,
    /// inverting the light-mode relationship.
    @Test(arguments: [false, true])
    func surfaceIsDistinguishableFromBackground(dark: Bool) {
        guard let surface = resolve("Surface", dark: dark),
              let background = resolve("Background", dark: dark) else {
            Issue.record("missing Surface or Background colorset")
            return
        }
        #expect(contrast(surface, background) > 1.05, "cards must be visible against the page")
    }
}
