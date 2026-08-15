import SwiftUI

/// The per-arm pack literals. They hold RAW values, never `Theme.*` reads: `Theme` resolves
/// through the active pack now, so a pack defined in terms of `Theme` would be a cycle.
extension DesignPack {
    /// The shipped design, exactly. Every value here is the literal the app carried before the
    /// pack existed — `DesignPackControlPinTests` asserts each one, so control cannot drift.
    static let control = DesignPack(
        appearance: nil,
        colors: DesignColors(
            accentDefault: .asset("BrandPrimary"),
            onPrimary: .asset("OnPrimary"),
            secondary: .asset("BrandSecondary"),
            accent: .asset("Accent"),
            background: .asset("Background"),
            surface: .asset("Surface"),
            textPrimary: .asset("TextPrimary"),
            textSecondary: .asset("TextSecondary"),
            error: .asset("Error"),
            success: .asset("Success"),
            warning: .asset("Warning"),
            wearGood: .asset("Success"),
            wearFair: .asset("Warning"),
            wearLow: .asset("Error"),
            shadow: .asset("ShadowColor")
        ),
        typography: DesignTypography(
            largeTitle: DesignFont(scale: .textStyle(.largeTitle), design: .rounded, weight: .bold),
            title: DesignFont(scale: .textStyle(.title2), design: .rounded, weight: .semibold),
            headline: DesignFont(scale: .textStyle(.headline), design: .rounded, weight: .semibold),
            body: DesignFont(scale: .textStyle(.body), design: .default, weight: .regular),
            caption: DesignFont(scale: .textStyle(.caption), design: .default, weight: .regular),
            mono: DesignFont(scale: .textStyle(.body), design: .monospaced, weight: .medium)
        ),
        spacing: DesignSpacing(xxs: 2, xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48),
        radius: DesignRadius(sm: 8, md: 12, lg: 16, full: 999),
        components: DesignComponents(
            card: DesignCardStyle(padding: 16, corner: DesignCorner(radius: 16), shadowRadius: 10, shadowOffset: 6),
            primaryButton: DesignButtonStyle(
                corner: DesignCorner(radius: 12),
                labelWeight: .semibold,
                verticalPadding: 16,
                borderWidth: 0,
                borderOpacity: 0
            ),
            secondaryButton: DesignButtonStyle(
                corner: DesignCorner(radius: 12),
                // nil: the ramp's own headline weight stands, which is what the button has always
                // rendered — an explicit `.semibold` here would only restate the ramp.
                labelWeight: nil,
                verticalPadding: 16,
                borderWidth: 1,
                borderOpacity: 0.15
            ),
            // A 29 radius on a 58 button is the circle the FAB has always been.
            floatingButton: DesignFloatingButtonStyle(
                diameter: 58,
                iconPointSize: 22,
                iconWeight: .bold,
                corner: DesignCorner(radius: 29),
                shadowRadius: 10,
                shadowOffset: 8
            ),
            tabBar: DesignTabBarStyle(background: nil, selectedTint: nil, unselectedTint: nil)
        ),
        structure: DesignStructure(
            // Derived from AppTab rather than restated, so the shipped tab bar has exactly ONE
            // source of truth. The pin test asserts the resulting labels and symbols literally.
            tabs: AppTab.allCases.map {
                DesignTabItem(tab: $0, title: $0.rawValue, systemImage: $0.icon)
            },
            showsDashboardTrendsRow: false,
            showsSettingsAccessory: false,
            framing: DesignFraming(
                recordTitle: nil,
                recordSubtitle: nil,
                handoverTitle: nil,
                handoverSubtitle: nil
            )
        )
    )

    /// Wave-1 challenger: "bold" — flatter, squarer, heavier. This is the PARTIAL PR-#23 pack,
    /// carried forward unchanged: epoch 1 is killed, and the full Underhood treatment lands in
    /// waves U1′–U4′ under epoch 2. Everything it does not name mirrors control, so the deltas
    /// stay exactly the four the pack shipped with.
    static let variantA = DesignPack(
        appearance: control.appearance,
        colors: control.colors,
        typography: control.typography,
        spacing: control.spacing,
        radius: control.radius,
        components: DesignComponents(
            card: DesignCardStyle(padding: 16, corner: DesignCorner(radius: 8), shadowRadius: 0, shadowOffset: 0),
            primaryButton: DesignButtonStyle(
                corner: DesignCorner(radius: 8),
                labelWeight: .bold,
                verticalPadding: 16,
                borderWidth: 0,
                borderOpacity: 0
            ),
            secondaryButton: control.components.secondaryButton,
            floatingButton: DesignFloatingButtonStyle(
                diameter: 58,
                iconPointSize: 22,
                iconWeight: .bold,
                corner: DesignCorner(radius: 16),
                shadowRadius: 0,
                shadowOffset: 0
            ),
            tabBar: control.components.tabBar
        ),
        structure: control.structure
    )
}
