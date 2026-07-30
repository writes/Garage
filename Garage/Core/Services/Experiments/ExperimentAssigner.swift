import CryptoKit
import Foundation

/// Pure deterministic assignment math. No state, no clock, no randomness — the SAME
/// (unit, experiment, epoch) always lands in the same bucket on every device and in any
/// analysis SQL that re-derives it. Tests pin exact hash outputs: the hash recipe is part of
/// the experiment contract, and a silent change would invisibly reshuffle every arm.
enum ExperimentAssigner {
    /// Fraction of users held out of PROACTIVE notifications to measure incrementality.
    /// User-created reminders are never suppressed — the holdout only gates system-initiated
    /// categories (none shipped yet); v1 sets the user property so the split exists in the
    /// data from day one.
    static let notificationHoldoutFraction = 0.10

    /// Uniform [0, 1) bucket for a unit within one experiment epoch. Recipe (FROZEN — v1):
    /// SHA-256 over UTF-8 of "v1:<experiment>:<epoch>:<unit>", big-endian first 8 bytes,
    /// divided by 2^64.
    static func bucket(unitID: String, experiment: ExperimentID, epoch: Int) -> Double {
        uniform(seed: "v1:\(experiment.rawValue):\(epoch):\(unitID)")
    }

    /// Weighted arm selection: normalized cumulative ranges over the allocation order.
    /// Empty/zero-weight allocations fall back to `.control` (never crash on a bad registry).
    static func arm(unitID: String, definition: ExperimentDefinition) -> ExperimentArm {
        let allocations = definition.allocations.filter { $0.weight > 0 }
        let totalWeight = allocations.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return .control }

        let sample = bucket(unitID: unitID, experiment: definition.id, epoch: definition.epoch)
        var cumulative = 0.0
        for allocation in allocations {
            cumulative += allocation.weight / totalWeight
            if sample < cumulative { return allocation.arm }
        }
        // Floating-point edge: a sample of ~0.999... can step past the last cumulative bound.
        return allocations[allocations.count - 1].arm
    }

    /// Independent hash (own salt) so holdout membership never correlates with any
    /// experiment's arm split.
    static func isInNotificationHoldout(unitID: String) -> Bool {
        uniform(seed: "v1:notif_holdout:\(unitID)") < notificationHoldoutFraction
    }

    private static func uniform(seed: String) -> Double {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        return Double(value) / Double(UInt64.max).nextUp
    }
}
