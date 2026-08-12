import Foundation
import Testing
@testable import Garage

/// P0.1/P0.2/P0.5 at the store boundary: a definition this build cannot render is treated as
/// killed, an override that re-weights an open epoch is ignored, and the arm/epoch reach the
/// crash reporter alongside the analytics user properties.
@MainActor
struct ExperimentStoreHardeningTests {
    private final class AnalyticsSpy: AnalyticsTracking {
        var events: [AnalyticsEvent] = []
        var properties: [UserProperty] = []
        func track(_ event: AnalyticsEvent) { events.append(event) }
        func setUserProperty(_ property: UserProperty) { properties.append(property) }
        func setEnabled(_: Bool) {}
    }

    /// Collects the refusals the production store would raise as `assertionFailure`, which
    /// would abort these tests — the refusal paths are exactly what they assert.
    private final class ViolationLog {
        var messages: [String] = []
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "experiment-hardening-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

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

    /// Writes the blob a previous launch would have persisted, so a test can start from a
    /// specific locked assignment instead of whatever this unit hashes to.
    private func seedAssignment(
        arm: String, epoch: Int, exposedEpochs: [Int] = [], in defaults: UserDefaults
    ) throws {
        let blob: [String: Any] = [
            "unitID": UUID().uuidString,
            "assignments": [
                "design_megatest": [
                    "arm": arm,
                    "epoch": epoch,
                    "exposedEpochs": exposedEpochs,
                    "surveySubmittedEpochs": []
                ]
            ]
        ]
        // ExperimentStore.storageKey, which is private.
        defaults.set(try JSONSerialization.data(withJSONObject: blob), forKey: "garage.experiments.v1")
    }

    private func makeStore(
        defaults: UserDefaults? = nil,
        bundled: ExperimentDefinition? = nil,
        analytics: AnalyticsSpy = AnalyticsSpy(),
        crashReporter: CrashReporterSpy = CrashReporterSpy(),
        violations: ViolationLog = ViolationLog()
    ) -> ExperimentStore {
        ExperimentStore(
            defaults: defaults ?? makeDefaults(),
            registry: ExperimentRegistry(definitions: [bundled ?? definition()]),
            analytics: analytics,
            crashReporter: crashReporter,
            onPolicyViolation: { violations.messages.append($0) }
        )
    }

    // MARK: - P0.1 silent-control hole

    @Test func anOverrideAllocatingASpareSlotKillsTheExperimentInsteadOfRenderingControl() {
        let analytics = AnalyticsSpy()
        let violations = ViolationLog()
        let store = makeStore(analytics: analytics, violations: violations)
        // Higher epoch, so the allocation clamp lets it through — the spare slot is what stops it.
        store.applyServerOverride([definition(epoch: 2, arms: [(.variantB, 1)])])

        #expect(store.arm(for: .designMegatest) == .control)
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(analytics.events.isEmpty)
        #expect(analytics.properties.isEmpty)
        #expect(!store.isSurveyAvailable(for: .designMegatest))
        #expect(violations.messages.contains { $0.contains("cannot render variant_b") })
    }

    @Test func aBundledDefinitionAllocatingASpareSlotIsKilledToo() {
        let analytics = AnalyticsSpy()
        let store = makeStore(bundled: definition(arms: [(.variantC, 1)]), analytics: analytics)
        #expect(store.arm(for: .designMegatest) == .control)
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(analytics.events.isEmpty)
    }

    @Test func aMixedRosterKillsTheExperimentEvenForAUserOnAnImplementedArm() throws {
        // The ROSTER-level kill earns its keep on the half that renders fine: suppressing only
        // the variant_b users would keep exposing the control users, silently turning the 50/50
        // the pre-registration froze into 100/0.
        let defaults = makeDefaults()
        try seedAssignment(arm: "control", epoch: 1, in: defaults)
        let analytics = AnalyticsSpy()
        let violations = ViolationLog()
        let store = makeStore(
            defaults: defaults,
            bundled: definition(arms: [(.control, 1), (.variantB, 1)]),
            analytics: analytics,
            violations: violations
        )
        #expect(store.arm(for: .designMegatest) == .control)
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(analytics.events.isEmpty)
        #expect(analytics.properties.isEmpty)
        #expect(violations.messages.contains { $0.contains("cannot render variant_b") })
    }

    @Test func aStickyAssignmentToADroppedArmIsSuppressedRatherThanMislabelled() throws {
        // An earlier build that implemented variantB locked the user onto it; this one dropped
        // the design. The ROSTER is clean (control/variantA), so only the persisted assignment
        // can betray the user — seeded directly, as that build would have written it.
        let defaults = makeDefaults()
        try seedAssignment(arm: "variant_b", epoch: 1, in: defaults)

        let analytics = AnalyticsSpy()
        let violations = ViolationLog()
        let store = makeStore(defaults: defaults, analytics: analytics, violations: violations)
        #expect(store.arm(for: .designMegatest) == .control)
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(analytics.events.isEmpty)
        #expect(analytics.properties.isEmpty)
        #expect(violations.messages.contains { $0.contains("stored arm variant_b") })
    }

    /// The survey follows the same suppression the rendering does: a user whose sticky arm this
    /// build cannot render experiences control and records nothing, so offering them the
    /// experiment survey would collect answers about an arm they never saw (cross-check finding —
    /// isSurveyAvailable previously keyed off effectiveDefinition and leaked past the guard).
    @Test func aSuppressedStickyAssignmentIsNotSurveyedEither() throws {
        let defaults = makeDefaults()
        try seedAssignment(arm: "variant_b", epoch: 1, exposedEpochs: [1], in: defaults)
        let store = makeStore(defaults: defaults)

        #expect(store.arm(for: .designMegatest) == .control)
        #expect(!store.isSurveyAvailable(for: .designMegatest))
    }

    /// Store-boundary companion to ExperimentPolicyTests' rollsBackTheEpoch rule (cross-check
    /// gap): the STORE must actually refuse a stale lower-epoch override, not just the policy.
    @Test func anOverrideWithAStaleLowerEpochIsIgnoredAndFallsBackToBundled() {
        let violations = ViolationLog()
        let store = makeStore(
            bundled: definition(epoch: 2, arms: [(.control, 1), (.variantA, 0)]),
            violations: violations
        )
        store.applyServerOverride([definition(epoch: 1, arms: [(.control, 0), (.variantA, 1)])])

        #expect(store.arm(for: .designMegatest) == .control)
        #expect(violations.messages.contains { $0.contains("rolls_back_the_epoch") })
    }

    // MARK: - P0.2 allocation clamp (client mirror)

    @Test func anOverrideReweightingTheOpenEpochIsIgnored() {
        // Bundled sends every user to control; the override tries to send every user to
        // variantA under the SAME epoch. The arm is resolved only AFTER the override lands, so
        // stickiness cannot mask an override that was wrongly adopted.
        let violations = ViolationLog()
        let store = makeStore(bundled: definition(arms: [(.control, 1), (.variantA, 0)]), violations: violations)
        store.applyServerOverride([definition(arms: [(.control, 0), (.variantA, 1)])])

        #expect(store.arm(for: .designMegatest) == .control)
        #expect(violations.messages.contains { $0.contains("reweights_an_open_epoch") })
    }

    @Test func anAlreadyLockedArmSurvivesARefusedReweight() {
        let store = makeStore()
        let lockedArm = store.arm(for: .designMegatest)
        store.applyServerOverride([definition(arms: [(.control, 1), (.variantA, 99)])])
        #expect(store.arm(for: .designMegatest) == lockedArm)
    }

    @Test func anOverrideRestatingTheBundledAllocationIsAccepted() {
        let violations = ViolationLog()
        let store = makeStore(violations: violations)
        store.applyServerOverride([definition()])
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(violations.messages.isEmpty)
    }

    @Test func aKillAtTheOpenEpochStillWinsWhateverAllocationItCarries() {
        let store = makeStore(bundled: definition(arms: [(.variantA, 1)]))
        #expect(store.arm(for: .designMegatest) == .variantA)
        store.applyServerOverride([definition(arms: [(.control, 1), (.variantA, 3)], isKilled: true)])
        #expect(store.arm(for: .designMegatest) == .control)
    }

    @Test func aHigherEpochOverrideMayReweight() {
        let violations = ViolationLog()
        let store = makeStore(bundled: definition(arms: [(.control, 1)]), violations: violations)
        #expect(store.arm(for: .designMegatest) == .control)
        store.applyServerOverride([definition(epoch: 2, arms: [(.variantA, 1)])])
        #expect(store.arm(for: .designMegatest) == .variantA)
        #expect(violations.messages.isEmpty)
    }

    // MARK: - P0.5 arm-resolved crash keys

    @Test func exposureStampsTheArmAndEpochOntoTheCrashReporter() {
        let crashReporter = CrashReporterSpy()
        let store = makeStore(bundled: definition(epoch: 3, arms: [(.variantA, 1)]), crashReporter: crashReporter)
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(crashReporter.experimentContexts.count == 1)
        #expect(crashReporter.experimentContexts.first?.arm == .variantA)
        #expect(crashReporter.experimentContexts.first?.epoch == 3)
    }

    @Test func aSuppressedExperimentStampsNoCrashContext() {
        let crashReporter = CrashReporterSpy()
        let store = makeStore(bundled: definition(arms: [(.variantB, 1)]), crashReporter: crashReporter)
        store.recordExposureIfNeeded(for: .designMegatest)
        #expect(crashReporter.experimentContexts.isEmpty)
    }
}
