import Observation
import SwiftUI

/// One coherent presentation variant for the design megatest — the FULL token surface plus the
/// closed set of structural chokepoints the arm manifest freezes. `Theme` reads nothing but the
/// active pack, so a variant restyles every screen with zero per-view edits, and business logic,
/// ViewModels, and services stay ARM-INVARIANT by construction.
///
/// `control` MUST remain byte-identical to the shipped design: control users are the baseline and
/// must see zero change. `DesignPackControlPinTests` pins every one of its tokens to the literal
/// the app shipped before the pack existed — that pin is the control-stability contract until
/// pixel snapshots arrive in Phase 3.
///
/// Packs are EXPERIMENT state (device-level, sticky, assigned by ExperimentStore), NOT account
/// personalization — so unlike AccentStore they deliberately do NOT reset on sign-out or account
/// switch: the assignment must survive both, and the accent a user picked in Pro theming still
/// layers on top via `Theme.Colors.primary` independently.
struct DesignPack: Equatable, Sendable {
    /// The appearance this pack commits to, applied ONCE at the experiment surface's root.
    /// `nil` — control — is "no preference", i.e. follow the system, which is what the app has
    /// always done: there is no other `preferredColorScheme` call anywhere.
    let appearance: ColorScheme?
    let colors: DesignColors
    let typography: DesignTypography
    let spacing: DesignSpacing
    let radius: DesignRadius
    let components: DesignComponents
    let structure: DesignStructure

    /// The pack a wave has DESIGNED for `arm`, or nil for a spare slot. Single source of truth for
    /// both `pack(for:)` and `isImplemented(_:)` — a second switch would let a new wave add a
    /// design in one place and leave the other claiming the arm is undesigned.
    private static func designedPack(for arm: ExperimentArm) -> DesignPack? {
        switch arm {
        case .control: return .control
        case .variantA: return .variantA
        case .variantB, .variantC: return nil
        }
    }

    /// Whether this BUILD renders `arm` as its own design. ExperimentStore refuses to run an
    /// experiment that allocates an unimplemented arm: rendering control while assignment and
    /// exposure label the user `variant_b` corrupts the analysis silently, without a build.
    static func isImplemented(_ arm: ExperimentArm) -> Bool {
        designedPack(for: arm) != nil
    }

    /// Spare slots render control. Unreachable in practice — ExperimentPolicy kills any experiment
    /// naming one before an arm is assigned — so this is defense in depth, not routing.
    static func pack(for arm: ExperimentArm) -> DesignPack {
        designedPack(for: arm) ?? .control
    }
}

/// The one observable every token read resolves through. Mirrors AccentStore's singleton-read
/// pattern: reads inside a SwiftUI body register an Observation dependency, so an emergency kill
/// switch flipping the pack back to control live-restyles without a relaunch.
@MainActor
@Observable
final class DesignPackStore {
    static let shared = DesignPackStore()

    private(set) var pack: DesignPack = .control

    func apply(arm: ExperimentArm) {
        apply(DesignPack.pack(for: arm))
    }

    /// Applies a pack directly. Kept narrow on purpose — arm resolution is ExperimentStore's job,
    /// and this exists so a pack can be exercised without an experiment (token routing tests, and
    /// the per-arm previews wave U1′ needs).
    func apply(_ pack: DesignPack) {
        self.pack = pack
    }
}
