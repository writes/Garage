import AuthenticationServices
import SwiftUI
import Testing
import UIKit
@testable import Garage

/// Routing coverage for the component hooks wave U1′ newly CONSUMED — the card hairline, the
/// primary button's border, the tab-bar chrome and the Sign-in-with-Apple style. Each was a field
/// nothing read (or, for SIWA, a hardcoded value in the view) before Underhood needed it.
///
/// Same probe method as `ThemeRoutingTests`: apply a pack that shares no value with control and
/// assert the seam follows it, so a hook wired to a literal — or to the wrong field — fails here.
/// Serialized, and every body is synchronous: `DesignPackStore.shared` and `UITabBar.appearance()`
/// are process-wide state.
@MainActor
@Suite(.serialized)
struct ComponentHookRoutingTests {
    private func withProbe(_ body: (DesignPack) -> Void) {
        let probe = DesignPack.routingProbe
        DesignPackStore.shared.apply(probe)
        defer { DesignPackStore.shared.apply(arm: .control) }
        body(probe)
    }

    /// The card's hairline IS the concept's `--line` token: the ink at the style's opacity, so it
    /// needs no colour role of its own. Wiring it to a literal grey, or to `surface`, fails here.
    @Test func theCardHairlineResolvesThroughTheActivePack() {
        withProbe { probe in
            let card = DesignPackStore.shared.pack.components.card
            #expect(card.borderWidth == probe.components.card.borderWidth)
            #expect(card.borderOpacity == probe.components.card.borderOpacity)
            #expect(card.borderColor == probe.colors.textPrimary.color.opacity(probe.components.card.borderOpacity))
        }

        // Control's zero width is what makes the unconditional stroke in CardModifier safe.
        #expect(DesignPackStore.shared.pack.components.card.borderWidth == 0)
    }

    /// Both buttons now read ONE definition of what a pack's border is — the live accent at the
    /// style's opacity — where the primary button used to ignore the two fields entirely.
    @Test func bothButtonBordersResolveThroughTheActivePack() {
        AccentStore.shared.apply(themeID: nil)
        defer { AccentStore.shared.apply(themeID: nil) }

        withProbe { probe in
            let components = DesignPackStore.shared.pack.components
            #expect(components.primaryButton.borderWidth == probe.components.primaryButton.borderWidth)
            #expect(
                components.primaryButton.borderColor
                    == probe.colors.accentDefault.color.opacity(probe.components.primaryButton.borderOpacity)
            )
            #expect(
                components.secondaryButton.borderColor
                    == probe.colors.accentDefault.color.opacity(probe.components.secondaryButton.borderOpacity)
            )

            // The border follows the ACCENT, not the pack default, once a user has picked one —
            // the same composition rule the fill obeys.
            AccentStore.shared.apply(themeID: AccentScheme.plum.rawValue)
            #expect(
                components.primaryButton.borderColor
                    == AccentScheme.plum.tint.opacity(probe.components.primaryButton.borderOpacity)
            )
        }
    }

    /// The tab-bar field SwiftUI cannot express. This assertion is END-TO-END: it reads the UIKit
    /// proxy the app actually renders from, so deleting the consumption in `DesignPackStore.apply`
    /// fails it — unlike a seam test, which would still pass.
    @Test func theUnselectedTabTintReachesTheUIKitProxy() {
        defer { DesignPackStore.shared.apply(arm: .control) }

        DesignPackStore.shared.apply(.variantA)
        guard let applied = UITabBar.appearance().unselectedItemTintColor,
              let token = DesignPack.variantA.components.tabBar.unselectedTint else {
            Issue.record("Underhood's unselected tab tint never reached the UIKit proxy")
            return
        }
        #expect(rgba(applied) == rgba(UIColor(token.color)))

        // And the kill switch has to CLEAR it: nil is the platform default control renders.
        DesignPackStore.shared.apply(arm: .control)
        #expect(UITabBar.appearance().unselectedItemTintColor == nil)
    }

    /// Compared component-wise: two `UIColor`s built from the same sRGB literal are not guaranteed
    /// to be `==` when they arrive through different colour spaces.
    private func rgba(_ color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }

    /// Control takes no branch in `garageTabBarChrome` at all — every field nil means the platform
    /// bar with nothing applied to it, which is the only shape of consumption that leaves control
    /// provably untouched.
    @Test func controlAsksForNoTabBarChromeAtAll() {
        let tabBar = DesignPack.control.components.tabBar
        #expect(tabBar.background == nil)
        #expect(tabBar.selectedTint == nil)
        #expect(tabBar.unselectedTint == nil)

        let underhood = DesignPack.variantA.components.tabBar
        #expect(underhood.background != nil)
        #expect(underhood.selectedTint != nil)
    }

    /// `LoginView` hardcoded `.black`, which Apple's HIG forbids on a dark background.
    ///
    /// `SignInWithAppleButton.Style` is an opaque struct of three static lets — not Equatable, no
    /// raw value, unmatchable by pattern — so the mapping is compared by its reflected description
    /// against the SDK's OWN statics, never against a restated literal. The three descriptions are
    /// asserted mutually distinct first, so the comparison cannot pass vacuously if that reflection
    /// ever collapses.
    @Test func theSignInWithAppleStyleResolvesThroughTheActivePack() {
        func describe(_ style: SignInWithAppleButton.Style) -> String { String(describing: style) }
        let black = describe(.black)
        let white = describe(.white)
        let whiteOutline = describe(.whiteOutline)
        #expect(Set([black, white, whiteOutline]).count == 3, "the SDK's three styles are not distinguishable")

        #expect(describe(DesignSignInWithAppleStyle.black.buttonStyle) == black)
        #expect(describe(DesignSignInWithAppleStyle.white.buttonStyle) == white)
        #expect(describe(DesignSignInWithAppleStyle.whiteOutline.buttonStyle) == whiteOutline)

        #expect(describe(DesignPackStore.shared.pack.components.signInWithApple.buttonStyle) == black)
        withProbe { probe in
            #expect(DesignPackStore.shared.pack.components.signInWithApple == probe.components.signInWithApple)
            #expect(describe(DesignPackStore.shared.pack.components.signInWithApple.buttonStyle) == whiteOutline)
        }
    }
}
