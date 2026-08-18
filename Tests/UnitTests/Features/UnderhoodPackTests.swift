import SwiftUI
import Testing
@testable import Garage

/// THE variant_a contract: every Underhood token pinned to the literal the concept ships.
///
/// Same job for the challenger that `DesignPackControlPinTests` does for control, and the same
/// method — each value restated BY HAND from `docs/research/2026-07-24_underhood_concept.html`
/// rather than read back from the pack (which would agree with itself no matter what it held) and
/// rather than built with the pack's own private `hex` helper (which would agree with a typo in the
/// extraction). A design change to this arm mid-experiment is a protocol violation, so this file is
/// what makes one loud.
@MainActor
struct UnderhoodPackTests {
    private let variant = DesignPack.variantA
    private let control = DesignPack.control

    /// The concept's CSS hex, restated as an sRGB token. Mirrors nothing in the app: this test owns
    /// its own conversion so the pin and the pack cannot share a mistake.
    private func css(_ hex: String, alpha: Double = 1) -> DesignColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return .srgb(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: alpha
        )
    }

    // MARK: - Appearance

    /// `--bg:#0D1217` lives behind `@media (prefers-color-scheme: dark)` and `.dark` in the concept,
    /// and the manifest commits the arm to it: ONE world, not a system-following pair.
    @Test func underhoodCommitsToTheSingleDarkWorld() {
        #expect(variant.appearance == .dark)
        #expect(variant.appearance != control.appearance)
    }

    // MARK: - Palette

    @Test func everyColourRoleCarriesItsConceptLiteral() {
        #expect(variant.colors.accentDefault == css("F2A33C"))   // Lamp Amber
        #expect(variant.colors.onPrimary == css("0D1217"))       // .btn.primary { color:#0D1217 }
        #expect(variant.colors.secondary == css("8B99A9"))       // Steel
        #expect(variant.colors.accent == css("F2A33C"))
        #expect(variant.colors.background == css("0D1217"))      // Bay
        #expect(variant.colors.textPrimary == css("EAEFF3"))     // Bone
        #expect(variant.colors.textSecondary == css("8B99A9"))
        #expect(variant.colors.error == css("E4572E"))           // --bad
        #expect(variant.colors.success == css("4CC38A"))         // --ok
    }

    /// The screen-level surface, NOT the prototype's `--psurf:#161E28` inner panel. Both are in the
    /// concept and only one is the page's card colour — pinned because picking the other is the
    /// single easiest extraction mistake to make here.
    @Test func theSurfaceIsTheScreenLevelOneNotThePrototypesInnerPanel() {
        #expect(variant.colors.surface == css("141B23"))
        #expect(variant.colors.surface != css("161E28"))
    }

    /// The concept has three status colours, not four: its `.warn` state is the amber itself.
    @Test func warningIsTheAmberAndTheWearScaleFollowsTheStatusTriple() {
        #expect(variant.colors.warning == css("F2A33C"))
        #expect(variant.colors.warning == variant.colors.accentDefault)
        #expect(variant.colors.wearGood == variant.colors.success)
        #expect(variant.colors.wearFair == variant.colors.warning)
        #expect(variant.colors.wearLow == variant.colors.error)
    }

    /// Elevation is a hairline in this world, so the shadow token is the concept's own
    /// `rgba(0,0,0,.45)` — deliberately NOT the `--line` token, which is a LIGHT ink tint and would
    /// paint a halo instead of a shadow on a near-black page.
    @Test func theShadowIsANearBlackAlphaAndNotTheLineToken() {
        #expect(variant.colors.shadow == .srgb(red: 0, green: 0, blue: 0, opacity: 0.45))
        #expect(variant.colors.shadow != css("EAEFF3", alpha: 0.10))
    }

    // MARK: - Type ramp

    /// The concept's ramp: system sans (NOT rounded — that is control's voice), display at 800,
    /// body at regular, and the data voice in mono. Held on text styles, so Dynamic Type survives.
    @Test func theTypeRampIsTheConceptsWeightsOnSystemSans() {
        func ramp(_ style: Font.TextStyle, _ design: Font.Design, _ weight: Font.Weight) -> DesignFont {
            DesignFont(scale: .textStyle(style), design: design, weight: weight)
        }

        #expect(variant.typography.largeTitle == ramp(.largeTitle, .default, .heavy))
        #expect(variant.typography.title == ramp(.title2, .default, .heavy))
        #expect(variant.typography.headline == ramp(.headline, .default, .bold))
        #expect(variant.typography.body == ramp(.body, .default, .regular))
        #expect(variant.typography.caption == ramp(.caption, .default, .regular))
        #expect(variant.typography.mono == ramp(.body, .monospaced, .semibold))
    }

    /// Every step stays dynamic-type native. A fixed size here would cap the ramp at whatever the
    /// concept's px value was and break accessibility text sizes in one arm only.
    @Test func noStepOfTheRampIsPinnedToAFixedPointSize() {
        for step in [
            variant.typography.largeTitle, variant.typography.title, variant.typography.headline,
            variant.typography.body, variant.typography.caption, variant.typography.mono
        ] {
            if case .fixed = step.scale {
                Issue.record("Underhood ramp step is a fixed size, which breaks Dynamic Type")
            }
        }
    }

    // MARK: - Shape

    /// "Everything else is square with hairline rules." `full` stays 999 because it means "pill".
    @Test func theRoundingScaleGoesSquareExceptThePillToken() {
        #expect(variant.radius == DesignRadius(sm: 0, md: 0, lg: 0, full: 999))
    }

    /// The concept's card clip-path is `polygon(0 0,calc(100% - 18px) 0,100% 18px,100% 100%,0 100%)`
    /// — ONE 18px cut, top right, and the corner set is the hook's default rather than an opt-in.
    @Test func cardsCarryTheConcepts18ptTopRightChamfer() {
        let card = variant.components.card
        #expect(card.corner == DesignCorner(radius: 0, chamfer: 18))
        #expect(card.corner.chamferedCorners == .topRight)
        #expect(card.corner.isChamfered)
        #expect(card.padding == 16)
    }

    /// Flat, with the `--line` hairline (ink at 10%) doing the separation the shadow used to.
    @Test func cardsAreFlatAndSeparatedByTheLineHairline() {
        let card = variant.components.card
        #expect(card.shadowRadius == 0)
        #expect(card.shadowOffset == 0)
        #expect(card.borderWidth == 1)
        #expect(card.borderOpacity == 0.10)
    }

    /// `.btn` / `.btn.primary`: a 12px cut, a 1px border, and 700 weight on the filled one only.
    @Test func bothButtonsCarryTheConcepts12ptCutAndHairline() {
        let primary = variant.components.primaryButton
        #expect(primary.corner == DesignCorner(radius: 0, chamfer: 12))
        #expect(primary.labelWeight == .bold)
        #expect(primary.borderWidth == 1)
        // The concept's primary border is the fill's own colour, i.e. full opacity on the accent.
        #expect(primary.borderOpacity == 1)

        let secondary = variant.components.secondaryButton
        #expect(secondary.corner == DesignCorner(radius: 0, chamfer: 12))
        #expect(secondary.labelWeight == .regular)
        #expect(secondary.borderWidth == 1)
        #expect(secondary.borderOpacity == 0.10)
        // Tap targets are not a token the manifest freed: both keep the shipped vertical padding.
        #expect(primary.verticalPadding == control.components.primaryButton.verticalPadding)
        #expect(secondary.verticalPadding == control.components.secondaryButton.verticalPadding)
        // Explicitly regular: nil would inherit this arm's BOLD headline ramp and bold both
        // buttons, but the concept bolds only `.btn.primary` (cross-check finding).
        #expect(secondary.labelWeight == .regular)
    }

    /// The dock FAB is a chamfered amber SQUARE (`clip-path` 12px), not control's circle — and the
    /// 58pt tap target survives the restyle.
    @Test func theFloatingButtonIsAChamferedSquareAtTheShippedDiameter() {
        let fab = variant.components.floatingButton
        #expect(fab.diameter == 58)
        #expect(fab.corner == DesignCorner(radius: 0, chamfer: 12))
        #expect(fab.corner.radius != fab.diameter / 2)
        #expect(fab.shadowRadius == 0)
        #expect(fab.shadowOffset == 0)
        // The glyph itself is part of the pin (cross-check finding: these two were mutable
        // without any test noticing).
        #expect(fab.iconPointSize == 22)
        #expect(fab.iconWeight == .bold)
    }

    // MARK: - Chrome

    /// The concept's dock: `rgba(10,14,18,.92)`, amber on, steel off.
    @Test func theTabBarCarriesTheConceptsDockChrome() {
        let tabBar = variant.components.tabBar
        #expect(tabBar.background == css("0A0E12", alpha: 0.92))
        #expect(tabBar.selectedTint == css("F2A33C"))
        #expect(tabBar.unselectedTint == css("8B99A9"))
    }

    /// Apple's HIG scopes the black button to light backgrounds; this world has none.
    @Test func theSignInWithAppleButtonIsWhiteOnTheDarkWorld() {
        #expect(variant.components.signInWithApple == .white)
        #expect(variant.components.signInWithApple != control.components.signInWithApple)
    }

    // MARK: - What U1' must NOT move

    /// U2′–U4′ structural treatment: IA remap, Hood trends row, settings accessory, framing copy.
    @Test func theStructureCarriesTheFullUnderhoodManifest() {
        #expect(variant.structure.showsDashboardTrendsRow)
        #expect(variant.structure.showsSettingsAccessory)
        #expect(variant.structure.tabs.map(\.tab) == [
            .dashboard, .log, .record, .garage, .handover
        ])
        #expect(variant.structure.tabs.map(\.title) == [
            "Hood", "Logbook", "Record", "Bay", "Handover"
        ])
        #expect(variant.structure.framing.recordTitle == "Record")
        #expect(variant.structure.framing.handoverTitle == "Handover")
        #expect(!variant.structure.visibleTabs.contains(.stats))
        #expect(!variant.structure.visibleTabs.contains(.settings))
    }

    /// Spacing is not one of the manifest's six token groups, so the two arms must share it: a
    /// spacing delta would change layout density in a way no registered difference accounts for.
    @Test func spacingMirrorsControlBecauseItIsNotAManifestTokenGroup() {
        #expect(variant.spacing == control.spacing)
    }

    /// The arm is REACHABLE — a designed pack, not a spare slot rendering control by accident.
    @Test func theArmResolvesToThisPack() {
        #expect(DesignPack.isImplemented(.variantA))
        #expect(DesignPack.pack(for: .variantA) == variant)
        #expect(variant != control)
    }
}
