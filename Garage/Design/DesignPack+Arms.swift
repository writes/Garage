import SwiftUI

/// The per-arm pack literals. They hold RAW values, never `Theme.*` reads: `Theme` resolves
/// through the active pack now, so a pack defined in terms of `Theme` would be a cycle.
extension DesignPack {
    /// A concept colour, written as the hex the concept's CSS ships so every literal below can be
    /// checked against `docs/research/2026-07-24_underhood_concept.html` by eye. Private on
    /// purpose: `UnderhoodPackTests` restates each hex by hand rather than reusing this, so the
    /// pin cannot agree with a typo in the extraction.
    private static func hex(_ value: UInt32, opacity: Double = 1) -> DesignColor {
        .srgb(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }

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
            // borderWidth 0: the shipped card has never drawn a border — elevation is its only
            // separation — so the new hairline hook renders nothing here.
            card: DesignCardStyle(
                padding: 16,
                corner: DesignCorner(radius: 16),
                shadowRadius: 10,
                shadowOffset: 6,
                borderWidth: 0,
                borderOpacity: 0
            ),
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
            tabBar: DesignTabBarStyle(background: nil, selectedTint: nil, unselectedTint: nil),
            // The button the login screen has always rendered, on the light world it was designed
            // for. Apple's HIG scopes `.black` to light backgrounds — see the variant below.
            signInWithApple: .black
        ),
        structure: DesignStructure(
            // Derived from the shipped tab roster rather than allCases, so Underhood-only identities
            // (record, handover) never leak into control when the enum grows.
            tabs: AppTab.controlTabs.map {
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

    /// **Underhood** (wave U1′) — the adopted concept's visual world, replacing the partial PR-#23
    /// "bold" pack epoch 1 killed. Every literal is extracted from
    /// `docs/research/2026-07-24_underhood_concept.html`; the arm manifest §1 freezes the six token
    /// groups this may move (palette, appearance, type ramp, shape, component styles, default
    /// accent). SPACING is not one of them, so it mirrors control, and `structure` mirrors control
    /// because every structural difference is waves U2′–U4′.
    static let variantA = DesignPack(
        // The concept ships a light set too, but it is chrome for the DOCUMENT — the product world
        // is the single committed dark one (manifest §1), not a second theme to follow the system
        // into.
        appearance: .dark,
        colors: DesignColors(
            // "Lamp Amber · the light" (concept identity palette). The pack DEFAULT only: an accent
            // explicitly picked in Pro theming still wins — Theme.Colors.primary composes them.
            accentDefault: hex(0xF2A33C),
            // The concept sets `color:#0D1217` on every amber-filled surface it draws — .btn.primary,
            // the dock FAB, the toast — so the ground colour IS this world's onPrimary. Measured
            // 9.03:1 on amber and >= 7.32:1 on all four Pro tints (UnderhoodContrastTests).
            onPrimary: hex(0x0D1217),
            // "Steel · secondary" (identity palette). Its one call site is WearItemBar's track fill
            // at 18%, which is the concept's `.tile .bar` hairline track.
            secondary: hex(0x8B99A9),
            // Underhood has ONE accent voice: the amber is both the default brand accent and the
            // semantic "attention" colour the concept paints chips, links and warn states in.
            accent: hex(0xF2A33C),
            background: hex(0x0D1217),   // "Bay · ground"
            // Screen-level surface. NOT the prototype's #161E28 inner panel, which is one step up
            // the concept's own ramp (--psurf) and would flatten card-on-page separation.
            surface: hex(0x141B23),
            textPrimary: hex(0xEAEFF3),  // "Bone · text"
            textSecondary: hex(0x8B99A9),
            error: hex(0xE4572E),        // --bad
            success: hex(0x4CC38A),      // --ok
            // The concept has no fourth status colour: its `.warn` state (service lights, tiles,
            // draft banners) is painted in the amber itself, so warning IS the accent here.
            warning: hex(0xF2A33C),
            // The wear scale reuses the status colours exactly as control does, which is also the
            // concept's `.tile.ok/.warn/.bad` triple.
            wearGood: hex(0x4CC38A),
            wearFair: hex(0xF2A33C),
            wearLow: hex(0xE4572E),
            // NOT the `--line` token: line is a LIGHT ink tint that serves the BORDER role in this
            // world (now a real hook on the card), and painting a light halo under a panel on a
            // near-black page is the opposite of elevation. Underhood expresses elevation with the
            // hairline instead, so every pack-driven shadow radius below is 0 and this token only
            // reaches the one call site that hardcodes a radius — where the concept's own elevation
            // shadow, `rgba(0,0,0,.45)`, is the right answer.
            shadow: hex(0x000000, opacity: 0.45)
        ),
        // Dynamic Type is preserved: the concept's fixed px ramp maps onto the SAME text styles
        // control uses, carrying the concept's WEIGHTS and its system-sans (not rounded) design.
        // Display is `font-weight:800` uppercase sans; body is SF Pro Text at regular; the data
        // voice — "every mileage, cost, and date in the product speaks in this voice" — is mono.
        typography: DesignTypography(
            largeTitle: DesignFont(scale: .textStyle(.largeTitle), design: .default, weight: .heavy),
            title: DesignFont(scale: .textStyle(.title2), design: .default, weight: .heavy),
            headline: DesignFont(scale: .textStyle(.headline), design: .default, weight: .bold),
            body: DesignFont(scale: .textStyle(.body), design: .default, weight: .regular),
            caption: DesignFont(scale: .textStyle(.caption), design: .default, weight: .regular),
            mono: DesignFont(scale: .textStyle(.body), design: .monospaced, weight: .semibold)
        ),
        // Not a manifest §1 token group — it mirrors control so the arms differ only in what the
        // manifest froze.
        spacing: control.spacing,
        // "Everything else is square with hairline rules" (concept identity, Geometry row): the
        // corner language is the chamfer, and the rounding scale goes flat. `full` stays 999 because
        // it means "pill", not "a large radius", and squaring it would make the token lie.
        radius: DesignRadius(sm: 0, md: 0, lg: 0, full: 999),
        components: DesignComponents(
            // 18pt top-right cut = the concept's card clip-path exactly
            // (`polygon(0 0,calc(100% - 18px) 0,100% 18px,100% 100%,0 100%)`, `.chamfer`/`.vehcard`).
            // Flat, with the `--line` hairline (ink at 10%) doing the separation the shadow did.
            card: DesignCardStyle(
                padding: 16,
                corner: DesignCorner(radius: 0, chamfer: 18),
                shadowRadius: 0,
                shadowOffset: 0,
                borderWidth: 1,
                borderOpacity: 0.10
            ),
            // `.btn.primary`: amber fill, 700 weight, and a 1px border in the fill's own colour —
            // which is why the border hook is honoured at full opacity rather than switched off.
            primaryButton: DesignButtonStyle(
                corner: DesignCorner(radius: 0, chamfer: 12),
                labelWeight: .bold,
                verticalPadding: 16,
                borderWidth: 1,
                borderOpacity: 1
            ),
            // `.btn`: the same silhouette, unfilled, behind a hairline. The weight is EXPLICIT
            // because nil means "the ramp's own" — and this arm's headline ramp is BOLD, which
            // would leak bold into the generic button. The concept declares no font-weight on
            // `.btn` (only `.btn.primary` carries 700), so the generic button is regular
            // (cross-check finding: nil here silently bolded both buttons).
            secondaryButton: DesignButtonStyle(
                corner: DesignCorner(radius: 0, chamfer: 12),
                labelWeight: .regular,
                verticalPadding: 16,
                borderWidth: 1,
                borderOpacity: 0.10
            ),
            // The dock FAB is a chamfered amber SQUARE (`clip-path` 12px), not a circle. Diameter
            // stays 58 — the shipped tap target is not a design token the manifest freed.
            floatingButton: DesignFloatingButtonStyle(
                diameter: 58,
                iconPointSize: 22,
                iconWeight: .bold,
                corner: DesignCorner(radius: 0, chamfer: 12),
                shadowRadius: 0,
                shadowOffset: 0
            ),
            // The concept's dock: a near-black translucent bar over the page, amber on the selected
            // item, steel on the rest.
            tabBar: DesignTabBarStyle(
                background: hex(0x0A0E12, opacity: 0.92),
                selectedTint: hex(0xF2A33C),
                unselectedTint: hex(0x8B99A9)
            ),
            // A black button on a #0D1217 page is invisible and off-HIG; white is the dark-world
            // answer (`.whiteOutline` is for light backgrounds, which this world does not have).
            signInWithApple: .white
        ),
        // U2′–U4′ structural treatment: IA remap, Hood/Bay/Logbook/Handover/Record framing,
        // D2-A trends row + settings accessory (arm manifest §2).
        structure: DesignStructure(
            tabs: [
                DesignTabItem(tab: .dashboard, title: "Hood", systemImage: "gauge.with.dots.needle.50percent"),
                DesignTabItem(tab: .log, title: "Logbook", systemImage: "book.closed"),
                DesignTabItem(tab: .record, title: "Record", systemImage: "plus"),
                DesignTabItem(tab: .garage, title: "Bay", systemImage: "square.grid.2x2"),
                DesignTabItem(tab: .handover, title: "Handover", systemImage: "doc.richtext")
            ],
            showsDashboardTrendsRow: true,
            showsSettingsAccessory: true,
            framing: DesignFraming(
                recordTitle: "Record",
                recordSubtitle: "Type it, say it, or scan it. Every non-manual path lands as a draft you commit.",
                handoverTitle: "Handover",
                handoverSubtitle: "The same CSV and PDF exports, framed for the next owner."
            )
        )
    )
}
