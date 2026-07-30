import Observation
import SwiftUI

/// One coherent presentation variant for the design megatest. A pack modulates the shared
/// chokepoints every card and primary control flows through (CardModifier, PrimaryButton,
/// FloatingAddButton) — so every screen inherits the variant with zero per-view edits, and
/// business logic, ViewModels, and services stay ARM-INVARIANT by construction.
///
/// `control` MUST remain byte-identical to the shipped design: control users are the baseline
/// and must see zero change. DesignPackEqualityTests pins its values to the Theme constants.
///
/// Packs are EXPERIMENT state (device-level, sticky, assigned by ExperimentStore), NOT account
/// personalization — so unlike AccentStore they deliberately do NOT reset on sign-out or
/// account switch: the assignment must survive both, and the accent a user picked in Pro
/// theming still layers on top via Theme.Colors.primary independently.
struct DesignPack: Equatable, Sendable {
    /// Corner radius for cards (`.garageCard()`).
    let cardRadius: CGFloat
    /// Card drop shadow radius; 0 renders flat.
    let cardShadowRadius: CGFloat
    /// Corner radius for primary buttons.
    let controlRadius: CGFloat
    /// Primary-button label weight.
    let primaryButtonWeight: Font.Weight
    /// The floating add button's silhouette: circle (control) vs rounded square.
    let fabIsCircular: Bool

    /// The shipped design, exactly. Values mirror Theme.Radius/Typography — pinned by test.
    static let control = DesignPack(
        cardRadius: Theme.Radius.lg,
        cardShadowRadius: 10,
        controlRadius: Theme.Radius.md,
        primaryButtonWeight: .semibold,
        fabIsCircular: true
    )

    /// Wave-1 challenger: "bold" — flatter, squarer, heavier. Deltas are deliberately visible
    /// (an indistinguishable variant measures nothing) while staying inside the HIG and the
    /// AA-contrast guarantees (colors are untouched — contrast tests keep applying to both).
    static let variantA = DesignPack(
        cardRadius: Theme.Radius.sm,
        cardShadowRadius: 0,
        controlRadius: Theme.Radius.sm,
        primaryButtonWeight: .bold,
        fabIsCircular: false
    )

    static func pack(for arm: ExperimentArm) -> DesignPack {
        switch arm {
        case .control: return .control
        case .variantA: return .variantA
        // Spare slots render control until a wave defines them (registry never allocates an
        // undesigned arm; this is defense in depth, not routing).
        case .variantB, .variantC: return .control
        }
    }
}

/// The one observable the design chokepoints read. Mirrors AccentStore's singleton-read
/// pattern (`Theme.Colors.primary`): reads inside a SwiftUI body register an Observation
/// dependency, so an emergency kill switch flipping the pack back to control live-restyles
/// without a relaunch.
@MainActor
@Observable
final class DesignPackStore {
    static let shared = DesignPackStore()

    private(set) var pack: DesignPack = .control

    func apply(arm: ExperimentArm) {
        pack = DesignPack.pack(for: arm)
    }
}
