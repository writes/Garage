import Foundation

/// Decides whether the experiment crash keys are written now, held, or cleared.
///
/// WHY THIS EXISTS. Same shape and same reason as AnalyticsConsentGate: the design arm resolves
/// before the first frame, while consent is only knowable after the async profile load. A plain
/// `guard isEnabled` — the rule `record`/`breadcrumb` use — would therefore drop the keys for
/// EVERY user, and the per-arm crash-free guardrail would have no measurement path at all,
/// which is the defect P0.5 exists to close.
///
/// Held values never reach Crashlytics: collection is off while disabled, and the gate returns
/// nothing to write. Unlike the analytics gate there is no identity-discard case — the arm is
/// device-scoped experiment state, unchanged by who is (or is not) signed in — so an opt-out
/// clears the LIVE keys while the held value survives a later opt-in.
///
/// Pure value type on purpose: the facade cannot be exercised in unit tests (a Crashlytics call
/// traps when Firebase was never configured), so the consent rules live where they can be tested.
struct ExperimentCrashKeyGate {
    /// Crashlytics custom keys to write. Nil fields mean "cleared" — rendered as EMPTY STRINGS
    /// by `armValue`/`epochValue`, because Crashlytics has no key-removal API and passing a nil
    /// Optional through its `Any` parameter records the boxed optional's description instead of
    /// clearing (cross-check finding: an opt-out would have written the literal text "nil" and
    /// left the user's arm legible forever).
    struct Keys: Equatable {
        let arm: String?
        let epoch: String?

        static let cleared = Keys(arm: nil, epoch: nil)

        /// What the facade actually writes — never an Optional, so the boxed-nil trap is
        /// unrepresentable at the call site.
        var armValue: String { arm ?? "" }
        var epochValue: String { epoch ?? "" }
    }

    private(set) var isEnabled = false
    private var pending: (arm: ExperimentArm, epoch: Int)?

    /// Whether a resolved arm is being held for a consent decision. Exposed for tests.
    var isHoldingContext: Bool { pending != nil }

    /// Returns the keys to write now, or nil when nothing should be written.
    mutating func setEnabled(_ enabled: Bool) -> Keys? {
        isEnabled = enabled
        guard enabled else { return .cleared }
        return pending.map { Keys(arm: $0.arm.rawValue, epoch: Self.epochValue($0.epoch)) }
    }

    /// Returns the keys to write now — nil while consent is unknown or refused.
    mutating func setContext(arm: ExperimentArm, epoch: Int) -> Keys? {
        pending = (arm, epoch)
        guard isEnabled else { return nil }
        return Keys(arm: arm.rawValue, epoch: Self.epochValue(epoch))
    }

    /// Rendered exactly as `UserProperty.experimentEpoch`, so a crash-key filter and an
    /// analytics cohort select the same population.
    private static func epochValue(_ epoch: Int) -> String {
        String(max(0, epoch))
    }
}
