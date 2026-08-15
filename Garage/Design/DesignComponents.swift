import SwiftUI

/// `.garageCard()` geometry. Colour comes from the palette (`Theme.Colors.surface`,
/// `Theme.Colors.shadow`), which is already pack-routed — a component style carries only what the
/// palette cannot express.
struct DesignCardStyle: Equatable, Sendable {
    let padding: CGFloat
    let corner: DesignCorner
    let shadowRadius: CGFloat
    let shadowOffset: CGFloat
    /// The concept separates panels with a hairline RULE instead of with elevation, so a card needs
    /// a border the shipped design never had. Control is 0 — a zero-width stroke paints nothing —
    /// which is why the hook can be consumed unconditionally without control moving a pixel.
    /// Deliberately NOT defaulted: a `let` with a default is dropped from the memberwise init, and
    /// every pack must state its own answer.
    let borderWidth: CGFloat
    /// Alpha for `borderColor`. The concept's `--line` IS the ink at a low alpha
    /// (`rgba(234,239,243,.10)`), so the hairline needs no colour role of its own.
    let borderOpacity: Double

    /// The hairline colour: the ink at this style's opacity, i.e. the concept's `--line` token.
    /// Reading it inside a body keeps it reactive, like every other token.
    @MainActor var borderColor: Color { Theme.Colors.textPrimary.opacity(borderOpacity) }
}

/// Primary/secondary button geometry. `labelWeight` is nil when the type ramp's own weight stands
/// (the shipped secondary button); a pack sets it to override the ramp for that one control.
struct DesignButtonStyle: Equatable, Sendable {
    let corner: DesignCorner
    let labelWeight: Font.Weight?
    let verticalPadding: CGFloat
    let borderWidth: CGFloat
    let borderOpacity: Double

    /// The label font: the ramp's headline, carrying this control's weight override when the pack
    /// sets one. Reading it inside a body keeps it reactive, like every other token.
    @MainActor var labelFont: Font {
        let headline = Theme.Typography.headline
        return labelWeight.map(headline.weight) ?? headline
    }

    /// The border this control strokes: the live accent at `borderOpacity` — exactly what the
    /// shipped secondary button has always drawn, hoisted here so the PRIMARY button can honour the
    /// same two fields instead of silently ignoring them (engine tri-review finding).
    @MainActor var borderColor: Color { Theme.Colors.primary.opacity(borderOpacity) }
}

/// The floating add button's silhouette and elevation. A `corner.radius` of half the diameter is
/// the shipped circle; anything smaller is a rounded square.
struct DesignFloatingButtonStyle: Equatable, Sendable {
    let diameter: CGFloat
    let iconPointSize: CGFloat
    let iconWeight: Font.Weight
    let corner: DesignCorner
    let shadowRadius: CGFloat
    let shadowOffset: CGFloat
}

/// Tab-bar chrome. Every value is nil for control — the platform bar, untouched — and a nil field
/// takes NO code path at all rather than applying a nil-valued modifier, so control cannot drift
/// through this hook. `background`/`selectedTint` are consumed in SwiftUI (`garageTabBarChrome`);
/// `unselectedTint` has no SwiftUI expression on iOS 17 and goes through the UIKit proxy from
/// `DesignPackStore.apply`, the single funnel every pack passes.
struct DesignTabBarStyle: Equatable, Sendable {
    let background: DesignColor?
    let selectedTint: DesignColor?
    let unselectedTint: DesignColor?
}

/// Which Sign-in-with-Apple button the pack renders. Apple's HIG permits the black button on light
/// backgrounds ONLY, so a pack that commits to a dark world has to be able to say so: `LoginView`
/// hardcoded `.black`, which on Underhood's #0D1217 page is a black button on black (engine
/// tri-review finding). Held as a design token rather than as `SignInWithAppleButton.Style` so the
/// design layer stays free of AuthenticationServices; `LoginView` owns the one-line mapping.
enum DesignSignInWithAppleStyle: Equatable, Sendable {
    case black
    case white
    case whiteOutline
}

/// The component-style hooks the arm manifest §1 names. Every shared control the whole app funnels
/// through reads its geometry from here, so a pack restyles all of them with no per-view edits.
struct DesignComponents: Equatable, Sendable {
    let card: DesignCardStyle
    let primaryButton: DesignButtonStyle
    let secondaryButton: DesignButtonStyle
    let floatingButton: DesignFloatingButtonStyle
    let tabBar: DesignTabBarStyle
    let signInWithApple: DesignSignInWithAppleStyle
}
