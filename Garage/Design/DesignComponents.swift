import SwiftUI

/// `.garageCard()` geometry. Colour comes from the palette (`Theme.Colors.surface`,
/// `Theme.Colors.shadow`), which is already pack-routed — a component style carries only what the
/// palette cannot express.
struct DesignCardStyle: Equatable, Sendable {
    let padding: CGFloat
    let corner: DesignCorner
    let shadowRadius: CGFloat
    let shadowOffset: CGFloat
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

/// Tab-bar chrome. Every value is nil for control — the platform bar, untouched — so the hook
/// exists for a pack that styles it without control ever leaving the system default. Unconsumed
/// in Phase 1 (nothing to consume: nil means "do not touch the bar").
struct DesignTabBarStyle: Equatable, Sendable {
    let background: DesignColor?
    let selectedTint: DesignColor?
    let unselectedTint: DesignColor?
}

/// The component-style hooks the arm manifest §1 names. Every shared control the whole app funnels
/// through reads its geometry from here, so a pack restyles all of them with no per-view edits.
struct DesignComponents: Equatable, Sendable {
    let card: DesignCardStyle
    let primaryButton: DesignButtonStyle
    let secondaryButton: DesignButtonStyle
    let floatingButton: DesignFloatingButtonStyle
    let tabBar: DesignTabBarStyle
}
