import Foundation
import Testing
@testable import Garage

/// Stickiness, epoch semantics, kill switch, exposure-once, and survey bookkeeping. All
/// in-memory (`defaults: nil` would lose persistence assertions, so a throwaway suite-named
/// UserDefaults instance is used and wiped per test).
@MainActor
struct ExperimentStoreTests {
    private final class AnalyticsSpy: AnalyticsTracking {
        var events: [AnalyticsEvent] = []
        var properties: [UserProperty] = []
        func track(_ event: AnalyticsEvent) { events.append(event) }
        func setUserProperty(_ property: UserProperty) { properties.append(property) }
        func setEnabled(_: Bool) {}
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "experiment-store-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func registry(
        epoch: Int = 1,
        arms: [(ExperimentArm, Double)] = [(.control, 1), (.variantA, 1)],
        isKilled: Bool = false
    ) -> ExperimentRegistry {
        ExperimentRegistry(definitions: [
            ExperimentDefinition(
                id: .designMegatest,
                epoch: epoch,
                allocations: arms.map { ArmAllocation(arm: $0.0, weight: $0.1) },
                isKilled: isKilled
            )
        ])
    }

    @Test func armIsStickyAcrossReinitialization() {
        let defaults = makeDefaults()
        let first = ExperimentStore(defaults: defaults, registry: registry(), analytics: AnalyticsSpy())
        let arm = first.arm(for: .designMegatest)
        let second = ExperimentStore(defaults: defaults, registry: registry(), analytics: AnalyticsSpy())
        #expect(second.arm(for: .designMegatest) == arm)
        #expect(second.unitID == first.unitID)
    }

    @Test func epochBumpKeepsASurvivingArm() {
        let defaults = makeDefaults()
        let first = ExperimentStore(defaults: defaults, registry: registry(epoch: 1), analytics: AnalyticsSpy())
        let arm = first.arm(for: .designMegatest)
        let bumped = ExperimentStore(defaults: defaults, registry: registry(epoch: 2), analytics: AnalyticsSpy())
        #expect(bumped.arm(for: .designMegatest) == arm)
    }

    @Test func epochBumpRehashesARetiredArm() {
        let defaults = makeDefaults()
        // Everyone starts on control, then control is retired — the only surviving arm is
        // variantA, so a re-hash is the ONLY way to reach it. (Rosters here stay inside the
        // implemented arms: allocating a spare slot now kills the experiment — see
        // ExperimentStoreHardeningTests.)
        let first = ExperimentStore(
            defaults: defaults,
            registry: registry(arms: [(.control, 1)]),
            analytics: AnalyticsSpy()
        )
        #expect(first.arm(for: .designMegatest) == .control)
        let retired = ExperimentStore(
            defaults: defaults,
            registry: registry(epoch: 2, arms: [(.variantA, 1)]),
            analytics: AnalyticsSpy()
        )
        #expect(retired.arm(for: .designMegatest) == .variantA)
    }

    @Test func killSwitchForcesControlButPreservesTheStoredAssignment() {
        let defaults = makeDefaults()
        // All-in on variantA so the stored assignment is deterministic.
        let store = ExperimentStore(
            defaults: defaults,
            registry: registry(arms: [(.variantA, 1)]),
            analytics: AnalyticsSpy()
        )
        #expect(store.arm(for: .designMegatest) == .variantA)

        let killed = ExperimentStore(
            defaults: defaults,
            registry: registry(arms: [(.variantA, 1)], isKilled: true),
            analytics: AnalyticsSpy()
        )
        #expect(killed.arm(for: .designMegatest) == .control)

        let restored = ExperimentStore(
            defaults: defaults,
            registry: registry(arms: [(.variantA, 1)]),
            analytics: AnalyticsSpy()
        )
        #expect(restored.arm(for: .designMegatest) == .variantA)
    }

    @Test func exposureFiresOncePerEpochWithArmAndPropertiesFirst() {
        let defaults = makeDefaults()
        let spy = AnalyticsSpy()
        let store = ExperimentStore(defaults: defaults, registry: registry(), analytics: spy)
        store.recordExposureIfNeeded(for: .designMegatest)
        store.recordExposureIfNeeded(for: .designMegatest)

        let exposures = spy.events.filter {
            if case .experimentExposure = $0 { return true } else { return false }
        }
        #expect(exposures.count == 1)
        let arm = store.arm(for: .designMegatest)
        #expect(exposures.first == .experimentExposure(experiment: .designMegatest, arm: arm, epoch: 1))
        #expect(spy.properties.contains(.designArm(arm)))
        #expect(spy.properties.contains(.experimentEpoch(1)))
    }

    @Test func exposureRefiresAfterAnEpochBump() {
        let defaults = makeDefaults()
        let spy1 = AnalyticsSpy()
        ExperimentStore(defaults: defaults, registry: registry(epoch: 1), analytics: spy1)
            .recordExposureIfNeeded(for: .designMegatest)
        let spy2 = AnalyticsSpy()
        ExperimentStore(defaults: defaults, registry: registry(epoch: 2), analytics: spy2)
            .recordExposureIfNeeded(for: .designMegatest)
        let exposedEpoch2 = spy2.events.contains {
            if case .experimentExposure(_, _, let epoch) = $0 { return epoch == 2 } else { return false }
        }
        #expect(exposedEpoch2)
    }

    @Test func killedExperimentNeverEmitsExposure() {
        let spy = AnalyticsSpy()
        let store = ExperimentStore(defaults: makeDefaults(), registry: registry(isKilled: true), analytics: spy)
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(spy.events.isEmpty)
    }

    @Test func serverOverrideKillSwitchForcesControlAndPersists() {
        let defaults = makeDefaults()
        let store = ExperimentStore(
            defaults: defaults,
            registry: registry(arms: [(.variantA, 1)]),
            analytics: AnalyticsSpy()
        )
        #expect(store.arm(for: .designMegatest) == .variantA)

        let killed = ExperimentDefinition(
            id: .designMegatest,
            epoch: 1,
            allocations: [ArmAllocation(arm: .variantA, weight: 1)],
            isKilled: true
        )
        #expect(store.applyServerOverride([killed]))
        #expect(store.arm(for: .designMegatest) == .control)
        // Idempotent re-application reports no change.
        #expect(!store.applyServerOverride([killed]))

        // The cached override survives a cold relaunch even though the BUNDLED registry
        // still says alive.
        let relaunched = ExperimentStore(
            defaults: defaults,
            registry: registry(arms: [(.variantA, 1)]),
            analytics: AnalyticsSpy()
        )
        #expect(relaunched.arm(for: .designMegatest) == .control)

        // Lifting the kill (empty override) restores the stored assignment.
        #expect(relaunched.applyServerOverride([]))
        #expect(relaunched.arm(for: .designMegatest) == .variantA)
    }

    @Test func serverOverrideEpochBumpRetiringTheArmRehashes() {
        let defaults = makeDefaults()
        let store = ExperimentStore(
            defaults: defaults,
            registry: registry(arms: [(.variantA, 1)]),
            analytics: AnalyticsSpy()
        )
        #expect(store.arm(for: .designMegatest) == .variantA)
        // A HIGHER epoch may carry a new roster; variantA is retired, so every user re-hashes
        // onto the only remaining arm.
        let retiring = ExperimentDefinition(
            id: .designMegatest,
            epoch: 2,
            allocations: [ArmAllocation(arm: .control, weight: 1)],
            isKilled: false
        )
        store.applyServerOverride([retiring])
        #expect(store.arm(for: .designMegatest) == .control)
    }

    @Test func surveyAvailabilityRequiresExposureAndFlipsOffOnSubmission() {
        let store = ExperimentStore(defaults: makeDefaults(), registry: registry(), analytics: AnalyticsSpy())
        #expect(!store.isSurveyAvailable(for: .designMegatest))
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(store.isSurveyAvailable(for: .designMegatest))
        store.markSurveySubmitted(for: .designMegatest)
        #expect(!store.isSurveyAvailable(for: .designMegatest))
    }
}
