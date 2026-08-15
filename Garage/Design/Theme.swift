import SwiftUI

/// The app's token vocabulary, and the only thing 400+ call sites read. Every token resolves
/// through the ACTIVE `DesignPack` (`DesignPackStore`), so a design arm restyles the whole app
/// without a single call site being edited.
///
/// Every token is a `@MainActor` computed property rather than a `static let` for one reason:
/// reading it inside a SwiftUI body registers an Observation dependency on the store, so an
/// emergency kill switch flipping the pack back to control live-restyles with no relaunch. It is
/// the mechanism `Theme.Colors.primary` has used for the accent since Phase-1 theming, now applied
/// to the whole surface. The same caveat therefore applies to all of them: only reads inside a
/// body are reactive — do not cache one in a stored `let`/init or bridge it to UIColor and expect
/// updates.
enum Theme {
    @MainActor private static var pack: DesignPack { DesignPackStore.shared.pack }

    enum Colors {
        /// The one themeable accent (Phase-1 in-Pro theming), composed with the active pack: an
        /// accent the user EXPLICITLY picked — including explicit Classic — wins in every pack;
        /// only a user with no choice on record takes the PACK's own default accent. For control
        /// that default is the very same `BrandPrimary` asset it has always been, so nothing
        /// moves; a pack with its own default accent gets it without disturbing the four Pro
        /// schemes (arm manifest §1, last row).
        @MainActor static var primary: Color {
            AccentStore.shared.explicitScheme?.tint ?? Theme.pack.colors.accentDefault.color
        }
        /// Foreground for content sitting ON a `primary` fill (filled buttons, the FAB).
        /// It exists because `primary` cannot serve both roles in dark mode: carrying white text
        /// needs luminance <= 0.183, while reading as text against the dark background needs
        /// >= 0.215 — no colour satisfies both. So dark mode lightens the accent and flips this
        /// foreground to near-black; light mode keeps it white. Never hardcode `.white` on a
        /// `primary` surface.
        @MainActor static var onPrimary: Color { Theme.pack.colors.onPrimary.color }
        @MainActor static var secondary: Color { Theme.pack.colors.secondary.color }
        @MainActor static var accent: Color { Theme.pack.colors.accent.color }
        @MainActor static var background: Color { Theme.pack.colors.background.color }
        @MainActor static var surface: Color { Theme.pack.colors.surface.color }
        @MainActor static var textPrimary: Color { Theme.pack.colors.textPrimary.color }
        @MainActor static var textSecondary: Color { Theme.pack.colors.textSecondary.color }
        @MainActor static var error: Color { Theme.pack.colors.error.color }
        @MainActor static var success: Color { Theme.pack.colors.success.color }
        @MainActor static var warning: Color { Theme.pack.colors.warning.color }
        @MainActor static var wearGood: Color { Theme.pack.colors.wearGood.color }
        @MainActor static var wearFair: Color { Theme.pack.colors.wearFair.color }
        @MainActor static var wearLow: Color { Theme.pack.colors.wearLow.color }
        /// Card/button elevation. Alpha lives in the token, so call sites must not add
        /// `.opacity()`. Reached as `Color.garageShadow` at every existing call site.
        @MainActor static var shadow: Color { Theme.pack.colors.shadow.color }
    }

    enum Spacing {
        @MainActor static var xxs: CGFloat { Theme.pack.spacing.xxs }
        @MainActor static var xs: CGFloat { Theme.pack.spacing.xs }
        @MainActor static var sm: CGFloat { Theme.pack.spacing.sm }
        @MainActor static var md: CGFloat { Theme.pack.spacing.md }
        @MainActor static var lg: CGFloat { Theme.pack.spacing.lg }
        @MainActor static var xl: CGFloat { Theme.pack.spacing.xl }
        @MainActor static var xxl: CGFloat { Theme.pack.spacing.xxl }
    }

    enum Typography {
        @MainActor static var largeTitle: Font { Theme.pack.typography.largeTitle.font }
        @MainActor static var title: Font { Theme.pack.typography.title.font }
        @MainActor static var headline: Font { Theme.pack.typography.headline.font }
        @MainActor static var body: Font { Theme.pack.typography.body.font }
        @MainActor static var caption: Font { Theme.pack.typography.caption.font }
        @MainActor static var mono: Font { Theme.pack.typography.mono.font }
    }

    enum Radius {
        @MainActor static var sm: CGFloat { Theme.pack.radius.sm }
        @MainActor static var md: CGFloat { Theme.pack.radius.md }
        @MainActor static var lg: CGFloat { Theme.pack.radius.lg }
        @MainActor static var full: CGFloat { Theme.pack.radius.full }
    }
}
