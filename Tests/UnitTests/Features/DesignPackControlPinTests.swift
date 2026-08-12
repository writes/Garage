import SwiftUI
import Testing
@testable import Garage

/// THE control-stability contract until pixel snapshots arrive in Phase 3.
///
/// Phase 1 moved every token out of `Theme`'s literals and into `DesignPack.control`. Nothing in
/// the build can tell whether a value survived that move intact — the app compiles either way, the
/// journeys pass either way, and control users would simply get a slightly different app than the
/// one they were enrolled into. So each token is pinned here to the literal the app shipped
/// BEFORE the refactor, restated by hand rather than read back from `Theme` (which now resolves
/// through this very pack and would agree with itself no matter what it held).
@MainActor
struct DesignPackControlPinTests {
    private let control = DesignPack.control

    /// No `preferredColorScheme` call existed anywhere before Phase 1, and control must keep it
    /// that way: nil is "no preference", i.e. follow the system.
    @Test func controlFollowsTheSystemAppearance() {
        #expect(control.appearance == nil)
    }

    @Test func everyColourRoleKeepsItsShippedAsset() {
        #expect(control.colors.accentDefault == .asset("BrandPrimary"))
        #expect(control.colors.onPrimary == .asset("OnPrimary"))
        #expect(control.colors.secondary == .asset("BrandSecondary"))
        #expect(control.colors.accent == .asset("Accent"))
        #expect(control.colors.background == .asset("Background"))
        #expect(control.colors.surface == .asset("Surface"))
        #expect(control.colors.textPrimary == .asset("TextPrimary"))
        #expect(control.colors.textSecondary == .asset("TextSecondary"))
        #expect(control.colors.error == .asset("Error"))
        #expect(control.colors.success == .asset("Success"))
        #expect(control.colors.warning == .asset("Warning"))
        // The wear scale deliberately reuses the status colorsets rather than owning three of its
        // own — pinned so a palette edit cannot quietly split them.
        #expect(control.colors.wearGood == .asset("Success"))
        #expect(control.colors.wearFair == .asset("Warning"))
        #expect(control.colors.wearLow == .asset("Error"))
        #expect(control.colors.shadow == .asset("ShadowColor"))
    }

    @Test func theTypeRampKeepsItsShippedStylesAndWeights() {
        func ramp(_ style: Font.TextStyle, _ design: Font.Design, _ weight: Font.Weight) -> DesignFont {
            DesignFont(scale: .textStyle(style), design: design, weight: weight)
        }

        #expect(control.typography.largeTitle == ramp(.largeTitle, .rounded, .bold))
        #expect(control.typography.title == ramp(.title2, .rounded, .semibold))
        #expect(control.typography.headline == ramp(.headline, .rounded, .semibold))
        #expect(control.typography.body == ramp(.body, .default, .regular))
        #expect(control.typography.caption == ramp(.caption, .default, .regular))
        #expect(control.typography.mono == ramp(.body, .monospaced, .medium))
    }

    @Test func theSpacingAndRadiusScalesKeepTheirShippedValues() {
        #expect(control.spacing == DesignSpacing(xxs: 2, xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48))
        #expect(control.radius == DesignRadius(sm: 8, md: 12, lg: 16, full: 999))
    }

    @Test func theCardKeepsItsShippedGeometry() {
        let card = control.components.card
        #expect(card.padding == 16)
        #expect(card.corner == DesignCorner(radius: 16, chamfer: 0))
        #expect(!card.corner.isChamfered)
        #expect(card.shadowRadius == 10)
        #expect(card.shadowOffset == 6)
    }

    @Test func bothButtonsKeepTheirShippedGeometry() {
        let primary = control.components.primaryButton
        #expect(primary.corner == DesignCorner(radius: 12, chamfer: 0))
        #expect(primary.labelWeight == .semibold)
        #expect(primary.verticalPadding == 16)
        #expect(primary.borderWidth == 0)

        let secondary = control.components.secondaryButton
        #expect(secondary.corner == DesignCorner(radius: 12, chamfer: 0))
        // nil, not `.semibold`: the shipped secondary button applies no weight of its own, and a
        // restated one would be a second source of truth for the ramp.
        #expect(secondary.labelWeight == nil)
        #expect(secondary.verticalPadding == 16)
        #expect(secondary.borderWidth == 1)
        #expect(secondary.borderOpacity == 0.15)
    }

    @Test func theFloatingButtonStaysTheShippedCircle() {
        let fab = control.components.floatingButton
        #expect(fab.diameter == 58)
        #expect(fab.iconPointSize == 22)
        #expect(fab.iconWeight == .bold)
        // Radius == half the diameter IS the circle; anything less is the rounded square variant_a
        // renders instead.
        #expect(fab.corner.radius == fab.diameter / 2)
        #expect(!fab.corner.isChamfered)
        #expect(fab.shadowRadius == 10)
        #expect(fab.shadowOffset == 8)
    }

    /// The system tab bar, untouched. A pack that wants to style it sets these; control never can.
    @Test func theTabBarKeepsThePlatformDefault() {
        #expect(control.components.tabBar == DesignTabBarStyle(background: nil, selectedTint: nil, unselectedTint: nil))
    }

    @Test func theStructureIsExactlyTodaysFiveTabsInTodaysOrder() {
        #expect(control.structure.tabs.map(\.tab) == [.dashboard, .log, .garage, .stats, .settings])
        #expect(control.structure.tabs.map(\.title) == ["Dashboard", "Log", "Garage", "Stats", "Settings"])
        #expect(control.structure.tabs.map(\.systemImage) == [
            "gauge.open.with.lines.needle.33percent",
            "list.bullet.clipboard",
            "car.fill",
            "chart.bar.fill",
            "gearshape.fill"
        ])
    }

    /// The unconsumed structural hooks. Control's answer to each is the shipped behaviour, so
    /// wiring a consumer in a later wave cannot move control by accident.
    @Test func everyUnconsumedStructuralHookAnswersWithTheShippedBehaviour() {
        #expect(!control.structure.showsDashboardTrendsRow)
        #expect(!control.structure.showsSettingsAccessory)
        #expect(control.structure.framing == DesignFraming(
            recordTitle: nil,
            recordSubtitle: nil,
            handoverTitle: nil,
            handoverSubtitle: nil
        ))
    }

    /// variant_a is the partial PR-#23 "bold" pack, carried forward unchanged (epoch 1 is killed;
    /// the full Underhood treatment lands in waves U1′–U4′). Pinning it to exactly those deltas is
    /// what keeps "everything else mirrors control" true — a further difference appearing here
    /// would be an unregistered treatment.
    @Test func variantACarriesOnlyThePartialBoldDeltas() {
        let variant = DesignPack.variantA
        #expect(variant.appearance == control.appearance)
        #expect(variant.colors == control.colors)
        #expect(variant.typography == control.typography)
        #expect(variant.spacing == control.spacing)
        #expect(variant.radius == control.radius)
        #expect(variant.structure == control.structure)
        #expect(variant.components.secondaryButton == control.components.secondaryButton)
        #expect(variant.components.tabBar == control.components.tabBar)

        #expect(variant.components.card.corner.radius == 8)
        #expect(variant.components.card.shadowRadius == 0)
        #expect(variant.components.primaryButton.corner.radius == 8)
        #expect(variant.components.primaryButton.labelWeight == .bold)
        #expect(variant.components.floatingButton.corner.radius == 16)
    }
}
