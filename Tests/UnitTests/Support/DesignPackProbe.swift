import SwiftUI
@testable import Garage

/// Distinct per role, so a token wired to the WRONG field of the pack fails routing instead of
/// passing on a value two roles happen to share.
private func probeColor(_ index: Double) -> DesignColor {
    .srgb(red: index / 100, green: 0.5, blue: 0.25, opacity: 1)
}

extension DesignPack {
    /// A pack that shares NO value with control. `ThemeRoutingTests` applies it and asserts every
    /// `Theme` token follows: a token left as a hardcoded literal — or pointed at the wrong pack
    /// field — cannot survive that, whereas comparing control against control would let both
    /// through.
    static let routingProbe = DesignPack(
        appearance: .dark,
        colors: DesignColors(
            accentDefault: probeColor(1),
            onPrimary: probeColor(2),
            secondary: probeColor(3),
            accent: probeColor(4),
            background: probeColor(5),
            surface: probeColor(6),
            textPrimary: probeColor(7),
            textSecondary: probeColor(8),
            error: probeColor(9),
            success: probeColor(10),
            warning: probeColor(11),
            wearGood: probeColor(12),
            wearFair: probeColor(13),
            wearLow: probeColor(14),
            shadow: probeColor(15)
        ),
        typography: DesignTypography(
            largeTitle: DesignFont(scale: .fixed(41), design: .monospaced, weight: .black),
            title: DesignFont(scale: .fixed(37), design: .serif, weight: .heavy),
            headline: DesignFont(scale: .fixed(31), design: .monospaced, weight: .thin),
            body: DesignFont(scale: .fixed(29), design: .serif, weight: .light),
            caption: DesignFont(scale: .fixed(23), design: .monospaced, weight: .ultraLight),
            mono: DesignFont(scale: .fixed(19), design: .serif, weight: .medium)
        ),
        spacing: DesignSpacing(xxs: 101, xs: 102, sm: 103, md: 104, lg: 105, xl: 106, xxl: 107),
        radius: DesignRadius(sm: 201, md: 202, lg: 203, full: 204),
        components: DesignComponents(
            card: DesignCardStyle(
                padding: 301,
                corner: DesignCorner(radius: 302, chamfer: 303),
                shadowRadius: 304,
                shadowOffset: 305,
                borderWidth: 306,
                borderOpacity: 0.31
            ),
            primaryButton: DesignButtonStyle(
                corner: DesignCorner(radius: 401, chamfer: 402),
                labelWeight: .ultraLight,
                verticalPadding: 403,
                borderWidth: 404,
                borderOpacity: 0.41
            ),
            secondaryButton: DesignButtonStyle(
                corner: DesignCorner(radius: 501, chamfer: 502),
                labelWeight: .black,
                verticalPadding: 503,
                borderWidth: 504,
                borderOpacity: 0.51
            ),
            floatingButton: DesignFloatingButtonStyle(
                diameter: 601,
                iconPointSize: 602,
                iconWeight: .light,
                corner: DesignCorner(radius: 603, chamfer: 604),
                shadowRadius: 605,
                shadowOffset: 606
            ),
            tabBar: DesignTabBarStyle(
                background: probeColor(16),
                selectedTint: probeColor(17),
                unselectedTint: probeColor(18)
            ),
            // Not control's `.black`, so a login screen that hardcodes the style fails routing.
            signInWithApple: .whiteOutline
        ),
        structure: DesignStructure(
            tabs: [DesignTabItem(tab: .garage, title: "Bay", systemImage: "wrench.fill")],
            showsDashboardTrendsRow: true,
            showsSettingsAccessory: true,
            framing: DesignFraming(
                recordTitle: "Record",
                recordSubtitle: "Log the ritual",
                handoverTitle: "Handover",
                handoverSubtitle: "Pass the keys"
            )
        )
    )
}
