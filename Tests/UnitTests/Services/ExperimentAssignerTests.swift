import Foundation
import Testing
@testable import Garage

/// The hash recipe is part of the experiment CONTRACT: analysis SQL re-derives assignments,
/// and a silent change to the recipe would invisibly reshuffle every arm mid-experiment. The
/// vectors below were computed independently (Python, SHA-256 over
/// "v1:<experiment>:<epoch>:<unit>", first 8 bytes big-endian / nextUp(2^64)) — they pin the
/// recipe itself, not merely determinism.
struct ExperimentAssignerTests {
    private let fiftyFifty = ExperimentDefinition(
        id: .designMegatest,
        epoch: 1,
        allocations: [
            ArmAllocation(arm: .control, weight: 1),
            ArmAllocation(arm: .variantA, weight: 1)
        ],
        isKilled: false
    )

    @Test func bucketMatchesIndependentlyComputedVectors() {
        let alpha = ExperimentAssigner.bucket(unitID: "unit-alpha", experiment: .designMegatest, epoch: 1)
        let bravo = ExperimentAssigner.bucket(unitID: "unit-bravo", experiment: .designMegatest, epoch: 1)
        let delta = ExperimentAssigner.bucket(unitID: "unit-delta", experiment: .designMegatest, epoch: 2)
        #expect(abs(alpha - 0.763273436074) < 1e-9)
        #expect(abs(bravo - 0.439530125134) < 1e-9)
        #expect(abs(delta - 0.950620692706) < 1e-9)
    }

    @Test func armAssignmentMatchesPinnedVectors() {
        #expect(ExperimentAssigner.arm(unitID: "unit-alpha", definition: fiftyFifty) == .variantA)
        #expect(ExperimentAssigner.arm(unitID: "unit-bravo", definition: fiftyFifty) == .control)
        #expect(ExperimentAssigner.arm(unitID: "unit-charlie", definition: fiftyFifty) == .variantA)
        #expect(ExperimentAssigner.arm(unitID: "unit-delta", definition: fiftyFifty) == .control)
        #expect(ExperimentAssigner.arm(unitID: "unit-echo", definition: fiftyFifty) == .variantA)
        #expect(ExperimentAssigner.arm(unitID: "unit-foxtrot", definition: fiftyFifty) == .control)
    }

    @Test func epochChangesTheHashSoRostersReshuffleOnlyOnEpochBump() {
        let epoch1 = ExperimentAssigner.bucket(unitID: "unit-alpha", experiment: .designMegatest, epoch: 1)
        let epoch2 = ExperimentAssigner.bucket(unitID: "unit-alpha", experiment: .designMegatest, epoch: 2)
        #expect(abs(epoch1 - epoch2) > 1e-9)
        #expect(abs(epoch2 - 0.343626211498) < 1e-9)
    }

    @Test func holdoutUsesAnIndependentSaltAndMatchesPins() {
        #expect(!ExperimentAssigner.isInNotificationHoldout(unitID: "unit-alpha"))
        #expect(!ExperimentAssigner.isInNotificationHoldout(unitID: "unit-delta"))
        #expect(ExperimentAssigner.isInNotificationHoldout(unitID: "unit-h29"))
    }

    @Test func weightsNeedNotSumToOne_andZeroWeightArmsNeverAdmit() {
        let skewed = ExperimentDefinition(
            id: .designMegatest,
            epoch: 1,
            allocations: [
                ArmAllocation(arm: .control, weight: 3),
                ArmAllocation(arm: .variantA, weight: 0)
            ],
            isKilled: false
        )
        for unit in ["unit-alpha", "unit-bravo", "unit-charlie", "unit-delta"] {
            #expect(ExperimentAssigner.arm(unitID: unit, definition: skewed) == .control)
        }
    }

    @Test func emptyOrAllZeroAllocationsFallBackToControl() {
        let empty = ExperimentDefinition(id: .designMegatest, epoch: 1, allocations: [], isKilled: false)
        #expect(ExperimentAssigner.arm(unitID: "unit-alpha", definition: empty) == .control)
    }

    @Test func splitIsRoughlyBalancedOverManyUnits() {
        var controls = 0
        for index in 0..<1000
        where ExperimentAssigner.arm(unitID: "balance-\(index)", definition: fiftyFifty) == .control {
            controls += 1
        }
        // 1000 fair coin flips land within [400, 600] except with probability < 1e-9.
        #expect(controls > 400 && controls < 600)
    }
}
