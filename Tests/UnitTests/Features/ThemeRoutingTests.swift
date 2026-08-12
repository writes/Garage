import SwiftUI
import Testing
@testable import Garage

/// Proves the plumbing: every `Theme` token resolves through the ACTIVE pack, not through a
/// literal it happens to agree with. Each test applies `DesignPack.routingProbe` — which shares no
/// value with control — and asserts the token follows, so a token wired to a hardcoded value or to
/// the wrong pack field fails here rather than in a variant nobody has built yet.
///
/// Serialized, and every body is synchronous: `DesignPackStore.shared` is process-wide state, so a
/// suspension point inside the probe window would let another main-actor test observe the probe.
@MainActor
@Suite(.serialized)
struct ThemeRoutingTests {
    /// Runs `body` with the probe pack applied, then restores control whatever happens.
    private func withProbe(_ body: (DesignPack) -> Void) {
        let probe = DesignPack.routingProbe
        DesignPackStore.shared.apply(probe)
        defer { DesignPackStore.shared.apply(arm: .control) }
        body(probe)
    }

    @Test func everyColourRoleResolvesThroughTheActivePack() {
        withProbe { probe in
            #expect(Theme.Colors.onPrimary == probe.colors.onPrimary.color)
            #expect(Theme.Colors.secondary == probe.colors.secondary.color)
            #expect(Theme.Colors.accent == probe.colors.accent.color)
            #expect(Theme.Colors.background == probe.colors.background.color)
            #expect(Theme.Colors.surface == probe.colors.surface.color)
            #expect(Theme.Colors.textPrimary == probe.colors.textPrimary.color)
            #expect(Theme.Colors.textSecondary == probe.colors.textSecondary.color)
            #expect(Theme.Colors.error == probe.colors.error.color)
            #expect(Theme.Colors.success == probe.colors.success.color)
            #expect(Theme.Colors.warning == probe.colors.warning.color)
            #expect(Theme.Colors.wearGood == probe.colors.wearGood.color)
            #expect(Theme.Colors.wearFair == probe.colors.wearFair.color)
            #expect(Theme.Colors.wearLow == probe.colors.wearLow.color)
            #expect(Theme.Colors.shadow == probe.colors.shadow.color)
        }
    }

    /// The three shadow call sites reach the palette through `Color.garageShadow`, so it has to
    /// route too — otherwise elevation is the one colour a pack cannot repaint.
    @Test func theShadowExtensionResolvesThroughTheActivePack() {
        withProbe { probe in
            #expect(Color.garageShadow == probe.colors.shadow.color)
        }
    }

    @Test func theTypeRampResolvesThroughTheActivePack() {
        withProbe { probe in
            #expect(Theme.Typography.largeTitle == probe.typography.largeTitle.font)
            #expect(Theme.Typography.title == probe.typography.title.font)
            #expect(Theme.Typography.headline == probe.typography.headline.font)
            #expect(Theme.Typography.body == probe.typography.body.font)
            #expect(Theme.Typography.caption == probe.typography.caption.font)
            #expect(Theme.Typography.mono == probe.typography.mono.font)
        }
    }

    @Test func spacingAndRadiusResolveThroughTheActivePack() {
        withProbe { probe in
            #expect(Theme.Spacing.xxs == probe.spacing.xxs)
            #expect(Theme.Spacing.xs == probe.spacing.xs)
            #expect(Theme.Spacing.sm == probe.spacing.sm)
            #expect(Theme.Spacing.md == probe.spacing.md)
            #expect(Theme.Spacing.lg == probe.spacing.lg)
            #expect(Theme.Spacing.xl == probe.spacing.xl)
            #expect(Theme.Spacing.xxl == probe.spacing.xxl)

            #expect(Theme.Radius.sm == probe.radius.sm)
            #expect(Theme.Radius.md == probe.radius.md)
            #expect(Theme.Radius.lg == probe.radius.lg)
            #expect(Theme.Radius.full == probe.radius.full)
        }
    }

    /// The composition rule (arm manifest §1, last row): a pack's accent is its DEFAULT — it
    /// applies to `.classic`, the scheme a user who has chosen nothing carries — while an accent
    /// explicitly picked in Pro theming wins inside whatever pack is active.
    @Test func theAccentComposesWithinTheActivePack() {
        AccentStore.shared.apply(themeID: nil)
        defer { AccentStore.shared.apply(themeID: nil) }

        #expect(Theme.Colors.primary == DesignPack.control.colors.accentDefault.color)

        withProbe { probe in
            #expect(Theme.Colors.primary == probe.colors.accentDefault.color)

            AccentStore.shared.apply(themeID: AccentScheme.marine.rawValue)
            #expect(Theme.Colors.primary == AccentScheme.marine.tint)
        }

        #expect(Theme.Colors.primary == AccentScheme.marine.tint)
    }

    /// EXPLICIT Classic is a choice, not the absence of one (tri-review B2): a user who
    /// deliberately picked Classic keeps BrandPrimary inside a pack whose own default differs —
    /// only "never chose" (nil themeID, sign-out wipe, bad persisted value) takes the pack
    /// default. Collapsing the two is exactly the defect this pins against.
    @Test func anExplicitClassicChoiceBeatsThePackDefaultAccent() {
        AccentStore.shared.apply(themeID: nil)
        defer { AccentStore.shared.apply(themeID: nil) }

        withProbe { probe in
            AccentStore.shared.apply(themeID: AccentScheme.classic.rawValue)
            #expect(Theme.Colors.primary == AccentScheme.classic.tint)
            #expect(Theme.Colors.primary != probe.colors.accentDefault.color)

            // The wipe restores the pack default — an account switch must not inherit the
            // previous user's explicitness any more than their accent.
            AccentStore.shared.apply(themeID: nil)
            #expect(Theme.Colors.primary == probe.colors.accentDefault.color)

            // An unrecognized persisted value is not a choice either.
            AccentStore.shared.apply(themeID: "not-a-scheme")
            #expect(Theme.Colors.primary == probe.colors.accentDefault.color)
        }
    }

    /// The appearance chokepoint's source. Control is nil — no preference, follow the system, the
    /// app's behaviour since launch — and a pack that commits to one world says so here.
    @Test func theAppearanceComesFromTheActivePack() {
        #expect(DesignPackStore.shared.pack.appearance == nil)

        withProbe { probe in
            #expect(DesignPackStore.shared.pack.appearance == probe.appearance)
            #expect(probe.appearance == .dark)
        }

        #expect(DesignPackStore.shared.pack.appearance == nil)
    }

    /// The routing chokepoint's source: the main tab view builds its tabs from exactly this array,
    /// so a pack re-labelling or re-ordering tabs moves the tab bar with no call-site edit. Control
    /// answers with the shipped five, which is why the journeys still find "Dashboard".
    @Test func theTabConfigurationComesFromTheActivePack() {
        #expect(DesignPackStore.shared.pack.structure.tabs.map(\.tab) == AppTab.allCases)

        withProbe { probe in
            #expect(DesignPackStore.shared.pack.structure.tabs == probe.structure.tabs)
            #expect(DesignPackStore.shared.pack.structure.item(for: .garage)?.title == "Bay")
            // A tab this pack does not surface has no item — the shape wave U4′ needs when
            // variant_a drops the Stats and Settings tabs (arm manifest §2.2, §2.3).
            #expect(DesignPackStore.shared.pack.structure.item(for: .stats) == nil)
        }

        #expect(DesignPackStore.shared.pack.structure.item(for: .stats)?.title == "Stats")
    }

    /// Applying an ARM must reach the same store the tokens read — the kill switch flips the arm,
    /// not the pack, and a store that ignored it would leave a killed variant rendering.
    @Test func applyingAnArmSwapsThePackTheTokensRead() {
        defer { DesignPackStore.shared.apply(arm: .control) }

        DesignPackStore.shared.apply(arm: .variantA)
        #expect(DesignPackStore.shared.pack == .variantA)

        DesignPackStore.shared.apply(arm: .control)
        #expect(DesignPackStore.shared.pack == .control)
    }

    /// Chamfer 0 — control everywhere — must keep producing the rounded rectangle every surface
    /// clipped to before the shape became a token.
    @Test func theCornerShapeIsRoundedUntilAPackAsksForAChamfer() {
        #expect(!DesignCorner(radius: 16).isChamfered)
        #expect(DesignCorner(radius: 16, chamfer: 4).isChamfered)

        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let rounded = DesignCorner(radius: 16).shape.path(in: rect)
        #expect(rounded == RoundedRectangle(cornerRadius: 16).path(in: rect))

        let chamfered = DesignCorner(radius: 16, chamfer: 12).shape.path(in: rect)
        #expect(chamfered == ChamferedRectangle(chamfer: 12).path(in: rect))
        #expect(chamfered != rounded)
    }
}
