import Foundation
import Testing
@testable import Garage

/// Contract coverage for the experimentation batch (2026-07-30): frozen names, definition
/// shapes, score clamping, the consent gate's new user-property semantics, and the DesignPack
/// control-equality pin.
struct ExperimentationAnalyticsTests {
    // MARK: - Name registry

    @Test func experimentationNamesAreRegisteredAndAllNamesStayUnique() {
        #expect(AnalyticsEvent.experimentationNames == [
            "experiment_exposure",
            "upsell_exposure",
            "feature_used",
            "notif_scheduled",
            "notif_opened",
            "notif_task_completed",
            "survey_submitted",
            "survey_dismissed"
        ])
        #expect(Set(AnalyticsEvent.allNames).count == AnalyticsEvent.allNames.count)
        #expect(AnalyticsEvent.allNames.contains("experiment_exposure"))
    }

    // MARK: - Definition shapes

    @Test func exposureDefinitionCarriesExperimentArmAndEpoch() {
        let definition = AnalyticsEvent.experimentExposure(
            experiment: .designMegatest, arm: .variantA, epoch: 3
        ).definition
        #expect(definition.name == "experiment_exposure")
        #expect(definition.firebaseParameters["experiment"] as? String == "design_megatest")
        #expect(definition.firebaseParameters["arm"] as? String == "variant_a")
        #expect(definition.firebaseParameters["epoch"] as? Int == 3)
        #expect(definition.parameters.contains(.schemaVersion(1)))
    }

    @Test func upsellExposureSharesTheSourceKeyWithThePaywallFunnel() {
        let definition = AnalyticsEvent.upsellExposure(source: .stats).definition
        #expect(definition.name == "upsell_exposure")
        #expect(definition.firebaseParameters["source"] as? String == "stats")
    }

    @Test func surveyScoresClampInto1Through5() {
        let definition = AnalyticsEvent.surveySubmitted(
            survey: .designMegatest, easeScore: 99, visualScore: -2, wouldSwitch: true
        ).definition
        #expect(definition.firebaseParameters["ease_score"] as? Int == 5)
        #expect(definition.firebaseParameters["visual_score"] as? Int == 1)
        #expect(definition.firebaseParameters["would_switch"] as? Int == 1)
    }

    @Test func notificationFunnelEventsShareTheCategoryKey() {
        for event in [
            AnalyticsEvent.notifScheduled(category: .reminderDue),
            .notifOpened(category: .reminderDue),
            .notifTaskCompleted(category: .reminderDue)
        ] {
            #expect(event.definition.firebaseParameters["category"] as? String == "reminder_due")
        }
    }

    @Test func featureUsedCarriesTheClosedFeatureEnum() {
        let definition = AnalyticsEvent.featureUsed(feature: .warranty).definition
        #expect(definition.name == "feature_used")
        #expect(definition.firebaseParameters["feature"] as? String == "warranty")
    }

    // MARK: - Consent gate: user properties

    @Test func gateHoldsPropertiesUntilConsentAndLatestValueWins() {
        var gate = AnalyticsConsentGate()
        #expect(gate.setUserProperty(.designArm(.control)).isEmpty)
        #expect(gate.setUserProperty(.designArm(.variantA)).isEmpty)
        #expect(gate.setUserProperty(.experimentEpoch(1)).isEmpty)
        #expect(gate.pendingPropertyCount == 2)

        let released = gate.setEnabledReleasingHeld(true)
        #expect(released.properties.count == 2)
        #expect(released.properties.contains(.designArm(.variantA)))
        #expect(!released.properties.contains(.designArm(.control)))
        // Enabled: subsequent sets pass straight through.
        #expect(gate.setUserProperty(.notifHoldout(true)) == [.notifHoldout(true)])
    }

    @Test func identityDiscardAndSessionSuppressionDropHeldProperties() {
        var gate = AnalyticsConsentGate()
        _ = gate.setUserProperty(.designArm(.variantA))
        gate.discardPending()
        #expect(gate.pendingPropertyCount == 0)

        _ = gate.setUserProperty(.designArm(.variantA))
        gate.suppressForSession()
        #expect(gate.pendingPropertyCount == 0)
        #expect(gate.setUserProperty(.designArm(.variantA)).isEmpty)
    }

    @Test func userPropertyWireNamesAndValuesAreStable() {
        #expect(UserProperty.designArm(.variantA).name == "design_arm")
        #expect(UserProperty.designArm(.variantA).value == "variant_a")
        #expect(UserProperty.experimentEpoch(4).name == "experiment_epoch")
        #expect(UserProperty.experimentEpoch(4).value == "4")
        #expect(UserProperty.notifHoldout(true).value == "1")
        #expect(UserProperty.notifHoldout(false).value == "0")
    }

    // MARK: - DesignPack

    @MainActor
    @Test func controlPackIsByteIdenticalToTheShippedDesign() {
        let control = DesignPack.control
        #expect(control.cardRadius == Theme.Radius.lg)
        #expect(control.cardShadowRadius == 10)
        #expect(control.controlRadius == Theme.Radius.md)
        #expect(control.primaryButtonWeight == .semibold)
        #expect(control.fabIsCircular)
        #expect(DesignPack.pack(for: .control) == control)
        // Undesigned spare slots render control — defense in depth, not routing. They must also
        // REPORT themselves undesigned, or ExperimentStore cannot refuse to label users with them.
        #expect(DesignPack.pack(for: .variantB) == control)
        #expect(DesignPack.pack(for: .variantC) == control)
        #expect(!DesignPack.isImplemented(.variantB))
        #expect(!DesignPack.isImplemented(.variantC))
        #expect(DesignPack.isImplemented(.control))
        #expect(DesignPack.isImplemented(.variantA))
        #expect(DesignPack.pack(for: .variantA) != control)
    }
}
