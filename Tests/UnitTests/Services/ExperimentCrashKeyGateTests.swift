import Foundation
import Testing
@testable import Garage

/// Consent semantics for the arm-resolved crash keys. The facade itself cannot be exercised
/// here (a Crashlytics call traps when Firebase was never configured), which is precisely why
/// the rules live in a pure gate.
struct ExperimentCrashKeyGateTests {
    @Test func nothingIsWrittenWhileConsentIsUnknown() {
        var gate = ExperimentCrashKeyGate()
        #expect(!gate.isEnabled)
        #expect(gate.setContext(arm: .variantA, epoch: 2) == nil)
        #expect(gate.isHoldingContext)
    }

    @Test func consentReleasesTheHeldArmAndEpoch() {
        var gate = ExperimentCrashKeyGate()
        _ = gate.setContext(arm: .variantA, epoch: 2)
        #expect(gate.setEnabled(true) == .init(arm: "variant_a", epoch: "2"))
    }

    @Test func consentWithNothingHeldWritesNothing() {
        var gate = ExperimentCrashKeyGate()
        #expect(gate.setEnabled(true) == nil)
    }

    @Test func anEnabledGatePassesSubsequentContextStraightThrough() {
        var gate = ExperimentCrashKeyGate()
        _ = gate.setEnabled(true)
        #expect(gate.setContext(arm: .control, epoch: 5) == .init(arm: "control", epoch: "5"))
    }

    @Test func onlyTheLatestHeldArmSurvives() {
        var gate = ExperimentCrashKeyGate()
        _ = gate.setContext(arm: .control, epoch: 1)
        _ = gate.setContext(arm: .variantA, epoch: 2)
        #expect(gate.setEnabled(true) == .init(arm: "variant_a", epoch: "2"))
    }

    @Test func anOptOutClearsTheLiveKeysButKeepsTheDeviceScopedArm() {
        var gate = ExperimentCrashKeyGate()
        _ = gate.setContext(arm: .variantA, epoch: 2)
        _ = gate.setEnabled(true)
        #expect(gate.setEnabled(false) == .cleared)
        // Opted out: still nothing written, even for a fresh resolution.
        #expect(gate.setContext(arm: .variantA, epoch: 2) == nil)
        // Re-consent restores it — the arm never depended on who was signed in.
        #expect(gate.setEnabled(true) == .init(arm: "variant_a", epoch: "2"))
    }

    /// The facade writes `armValue`/`epochValue`, never the raw optionals: Crashlytics has no
    /// key-removal API, and a nil Optional through its `Any` parameter records the boxed
    /// optional's description — an opt-out would have written the literal text "nil" and left
    /// the user's arm legible forever (cross-check finding).
    @Test func clearedKeysRenderAsEmptyStringsNeverBoxedNils() {
        #expect(ExperimentCrashKeyGate.Keys.cleared.armValue.isEmpty)
        #expect(ExperimentCrashKeyGate.Keys.cleared.epochValue.isEmpty)
        let live = ExperimentCrashKeyGate.Keys(arm: "variant_a", epoch: "2")
        #expect(live.armValue == "variant_a")
        #expect(live.epochValue == "2")
    }

    @Test func theEpochRendersExactlyAsTheAnalyticsUserProperty() {
        var gate = ExperimentCrashKeyGate()
        _ = gate.setEnabled(true)
        #expect(gate.setContext(arm: .control, epoch: 4)?.epoch == UserProperty.experimentEpoch(4).value)
        #expect(gate.setContext(arm: .control, epoch: -1)?.epoch == UserProperty.experimentEpoch(-1).value)
    }
}
