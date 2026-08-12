import Foundation

/// Why a fetched server override must not replace its bundled definition. Non-nil = the
/// override is treated as absent and the bundled definition stands.
enum ExperimentOverrideRejection: String, Equatable, Sendable {
    /// Names an experiment this build does not bundle, so there is no allocation to validate
    /// it against.
    case unknownExperiment = "unknown_experiment"
    /// Re-weights an OPEN epoch. The pre-registration freezes an epoch's allocation: changing
    /// weights without bumping the epoch invalidates the SRM check and every assignment
    /// probability already recorded under that epoch. Only a kill may change an open epoch.
    case reweightsAnOpenEpoch = "reweights_an_open_epoch"
    /// A stale document at an OLDER epoch carrying something other than a kill; rolling the
    /// epoch backwards re-hashes users into a retired roster.
    case rollsBackTheEpoch = "rolls_back_the_epoch"
    /// A non-kill override at the epoch of a bundled KILL. A bundled kill is a build-level
    /// verdict (epoch 1 was killed by the operator and the bundle records it); the only way
    /// forward is a NEW epoch in an enrollment build — a server document cannot resurrect a
    /// roster this binary considers closed.
    case revivesAKilledEpoch = "revives_a_killed_epoch"
}

/// The rules an effective experiment definition must satisfy before this build will run it.
/// Pure and stateless: ExperimentStore owns the state, this owns the judgement — so every
/// branch is exercisable without UserDefaults, analytics, or a store instance.
enum ExperimentPolicy {
    /// Allocation clamp. Mirrored server-side in
    /// `CloudFunctions/src/functions/experimentConfig.ts`; ExperimentContractTests diffs the two
    /// sources so the rule cannot drift to one side.
    ///
    /// Allocation comparison is ORDER-SENSITIVE by design — the assigner walks allocations as
    /// cumulative ranges, so reordering the same weights reshuffles which users land where.
    static func rejection(
        of override: ExperimentDefinition,
        against bundled: ExperimentDefinition?
    ) -> ExperimentOverrideRejection? {
        guard let bundled else { return .unknownExperiment }
        // The epoch-bump path stays open: a higher epoch is a NEW roster, analyzed as fresh
        // exposures, and an unrenderable arm inside it is caught by `unrenderableArms`.
        if override.epoch > bundled.epoch { return nil }
        // A kill is always honoured — it is the one change that cannot wait for a build, and
        // it only ever moves users toward control.
        if override.isKilled { return nil }
        // A killed bundled epoch cannot be re-opened from the server at the same (or a lower)
        // epoch — re-opening is an epoch bump in an enrollment build, never a document edit.
        if bundled.isKilled { return .revivesAKilledEpoch }
        if override.epoch < bundled.epoch { return .rollsBackTheEpoch }
        return override.allocations == bundled.allocations ? nil : .reweightsAnOpenEpoch
    }

    /// Whether this BUILD renders `arm` as its own design for `id`. The design megatest's arms
    /// are DesignPack slots: `variant_b`/`variant_c` are spares no shipped wave has designed and
    /// DesignPack falls back to control for them. Rendering control while assignment and
    /// exposure label the user `variant_b` is silent data corruption without a build, so an
    /// experiment naming one is killed for the session instead.
    static func canRender(_ arm: ExperimentArm, for id: ExperimentID) -> Bool {
        switch id {
        case .designMegatest: return DesignPack.isImplemented(arm)
        }
    }

    /// Arms taking live traffic that this build cannot render. Zero-weight allocations are
    /// excluded: they receive no new users, so they cannot mislabel anyone.
    static func unrenderableArms(in definition: ExperimentDefinition) -> [ExperimentArm] {
        definition.activeArms
            .filter { !canRender($0, for: definition.id) }
            .sorted { $0.rawValue < $1.rawValue }
    }
}
