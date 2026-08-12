import Foundation
import Testing
@testable import Garage

/// The two judgements that decide whether a server document may change a running split, tested
/// without a store: the allocation clamp and the unrenderable-arm rule.
struct ExperimentPolicyTests {
    private func definition(
        epoch: Int = 1,
        arms: [(ExperimentArm, Double)] = [(.control, 1), (.variantA, 1)],
        isKilled: Bool = false
    ) -> ExperimentDefinition {
        ExperimentDefinition(
            id: .designMegatest,
            epoch: epoch,
            allocations: arms.map { ArmAllocation(arm: $0.0, weight: $0.1) },
            isKilled: isKilled
        )
    }

    // MARK: - Allocation clamp

    @Test func anOverrideWithNoBundledCounterpartIsRefused() {
        #expect(ExperimentPolicy.rejection(of: definition(), against: nil) == .unknownExperiment)
    }

    @Test func anOpenEpochAcceptsOnlyTheBundledAllocation() {
        let bundled = definition()
        #expect(ExperimentPolicy.rejection(of: definition(), against: bundled) == nil)
        #expect(ExperimentPolicy.rejection(
            of: definition(arms: [(.control, 1), (.variantA, 9)]), against: bundled
        ) == .reweightsAnOpenEpoch)
        // Same split, rescaled — still refused: only an exact restatement proves nothing moved.
        #expect(ExperimentPolicy.rejection(
            of: definition(arms: [(.control, 50), (.variantA, 50)]), against: bundled
        ) == .reweightsAnOpenEpoch)
        // Roster change under the open epoch.
        #expect(ExperimentPolicy.rejection(
            of: definition(arms: [(.control, 1)]), against: bundled
        ) == .reweightsAnOpenEpoch)
    }

    @Test func anOpenEpochRefusesAReorderBecauseOrderDecidesWhoLandsWhere() {
        // The assigner walks allocations as cumulative ranges, so the same weights in a
        // different order reshuffle every user.
        #expect(ExperimentPolicy.rejection(
            of: definition(arms: [(.variantA, 1), (.control, 1)]), against: definition()
        ) == .reweightsAnOpenEpoch)
    }

    @Test func aKillIsHonouredAtAnyEpochAndWhateverWeightsItCarries() {
        let bundled = definition(epoch: 4)
        #expect(ExperimentPolicy.rejection(
            of: definition(epoch: 4, arms: [(.variantA, 7)], isKilled: true), against: bundled
        ) == nil)
        #expect(ExperimentPolicy.rejection(
            of: definition(epoch: 1, arms: [(.variantA, 7)], isKilled: true), against: bundled
        ) == nil)
    }

    @Test func aHigherEpochMayCarryANewAllocation() {
        #expect(ExperimentPolicy.rejection(
            of: definition(epoch: 2, arms: [(.control, 3), (.variantA, 1)]), against: definition()
        ) == nil)
    }

    /// The bundled epoch-1 kill (operator, 2026-08-11T19:34Z) is a build-level verdict: a
    /// server document restating the same epoch open again — even with the exact bundled
    /// allocation — must not resurrect the closed roster. Re-opening is an epoch bump in an
    /// enrollment build.
    @Test func aKilledBundledEpochCannotBeRevivedByADocumentEdit() {
        let killedBundle = definition(isKilled: true)
        #expect(ExperimentPolicy.rejection(
            of: definition(), against: killedBundle
        ) == .revivesAKilledEpoch)
        // A lower-epoch non-kill against a killed bundle is a revival too, not a rollback.
        #expect(ExperimentPolicy.rejection(
            of: definition(epoch: 0), against: killedBundle
        ) == .revivesAKilledEpoch)
        // Restating the kill is fine, and the epoch-bump path stays open for enrollment.
        #expect(ExperimentPolicy.rejection(
            of: definition(isKilled: true), against: killedBundle
        ) == nil)
        #expect(ExperimentPolicy.rejection(
            of: definition(epoch: 2), against: killedBundle
        ) == nil)
    }

    /// The shipped bundle itself records the epoch-1 kill — a fresh install renders control
    /// before its first registry fetch, not the retired epoch-1 challenger.
    @Test func theShippedBundleRecordsTheEpochOneKill() {
        #expect(ExperimentRegistry.bundled.definition(for: .designMegatest)?.isKilled == true)
    }

    @Test func aStaleLowerEpochMayNotRollTheRosterBack() {
        // Even an exact restatement of the older allocation: adopting it would drag the client
        // back onto a retired epoch and re-expose everyone under it.
        #expect(ExperimentPolicy.rejection(
            of: definition(epoch: 1), against: definition(epoch: 2)
        ) == .rollsBackTheEpoch)
    }

    // MARK: - Unrenderable arms

    @Test func onlyTheArmsThisBuildDesignedAreRenderable() {
        #expect(ExperimentPolicy.canRender(.control, for: .designMegatest))
        #expect(ExperimentPolicy.canRender(.variantA, for: .designMegatest))
        #expect(!ExperimentPolicy.canRender(.variantB, for: .designMegatest))
        #expect(!ExperimentPolicy.canRender(.variantC, for: .designMegatest))
    }

    @Test func spareSlotsTakingTrafficAreReportedAsUnrenderable() {
        #expect(ExperimentPolicy.unrenderableArms(in: definition()).isEmpty)
        #expect(ExperimentPolicy.unrenderableArms(
            in: definition(arms: [(.control, 1), (.variantB, 1), (.variantC, 1)])
        ) == [.variantB, .variantC])
    }

    @Test func aZeroWeightSpareSlotIsNotUnrenderableBecauseItTakesNoUsers() {
        #expect(ExperimentPolicy.unrenderableArms(
            in: definition(arms: [(.control, 1), (.variantA, 1), (.variantB, 0)])
        ).isEmpty)
    }
}
