import Foundation

/// One arm's share of traffic. Weights are relative (they need not sum to 1); the assigner
/// normalizes. An arm absent from an experiment's allocation list receives no NEW users but
/// existing sticky assignments to it remain valid until the epoch retires it.
struct ArmAllocation: Equatable, Sendable, Codable {
    let arm: ExperimentArm
    let weight: Double
}

/// A single experiment's shape for one epoch. The EPOCH is the roster version: any change to
/// the arm set bumps it, existing users keep their arm when it survives, and users whose arm
/// was retired re-hash across the new roster (analyzed as fresh exposures — the plan's
/// tournament/wave policy).
struct ExperimentDefinition: Equatable, Sendable, Codable {
    let id: ExperimentID
    let epoch: Int
    let allocations: [ArmAllocation]
    /// Emergency stop: forces every user to `.control` (the current shipped design) without a
    /// re-hash, leaving stored assignments intact so lifting the switch restores them.
    let isKilled: Bool

    var activeArms: Set<ExperimentArm> {
        Set(allocations.filter { $0.weight > 0 }.map(\.arm))
    }

    /// The same definition with the emergency stop engaged. Lets a client-side policy failure
    /// (an arm this build cannot render) ride the EXISTING kill path — control renders, no
    /// exposure, no assignment churn — instead of adding a parallel suppression branch.
    func killed() -> ExperimentDefinition {
        ExperimentDefinition(id: id, epoch: epoch, allocations: allocations, isKilled: true)
    }
}

/// The registry every launch consults. v1 is BUNDLED (compiled into the binary): at
/// review-phase cadence the roster changes with TestFlight builds anyway, and a bundled
/// registry cannot be broken by a network failure at the moment of first paint. A
/// server-override fetch (App-Check-only callable) is the documented follow-up for
/// out-of-band kill switches — see the Option A plan §9.
struct ExperimentRegistry: Equatable, Sendable {
    let definitions: [ExperimentDefinition]

    func definition(for id: ExperimentID) -> ExperimentDefinition? {
        definitions.first { $0.id == id }
    }

    /// The shipped roster. Epoch 1 of the design megatest was KILLED server-side by the
    /// operator on 2026-08-11T19:34Z (epoch-2 addendum records it) — the bundle must agree,
    /// or a fresh install renders the partial epoch-1 challenger between first paint and its
    /// first registry fetch and logs quarantine-only exposure rows. A killed bundled epoch is
    /// silent control everywhere (P0.1 semantics: sticky assignments suppressed, surveys
    /// included). Epoch 2 re-opens ONLY via a deliberate bundle bump in the enrollment build,
    /// with the allocations the addendum registers.
    static let bundled = ExperimentRegistry(definitions: [
        ExperimentDefinition(
            id: .designMegatest,
            epoch: 1,
            allocations: [
                ArmAllocation(arm: .control, weight: 1),
                ArmAllocation(arm: .variantA, weight: 1)
            ],
            isKilled: true
        )
    ])
}
