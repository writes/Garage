import Observation

/// The app's one haptic surface. Call sites `fire(_:)`; a SINGLE `.sensoryFeedback` cluster on
/// ContentView observes the counters and performs the actual feedback.
///
/// The indirection is not decoration — it is the only shape that works here. `.sensoryFeedback`
/// fires when a value observed by a LIVE view changes, and every event worth confirming happens in
/// the same transaction that tears its own host down: an entry-form save calls
/// `router.dismissSheet()`, a vehicle save calls `dismiss()`. A modifier on the form observes a
/// change that arrives as the form is being removed, which is exactly when it is least likely to
/// be honoured. Counters on a surface that outlives every sheet, observed by the persistent tab
/// host, do not have that race.
///
/// Deliberately NOT wired to purchase or paywall. The purchase path has several early returns
/// before an entitlement is actually granted, and a success buzz on any of them is a false
/// confirmation on the money path — the one place a wrong signal costs the user something.
@MainActor
@Observable
final class FeedbackCenter {
    static let shared = FeedbackCenter()

    enum Kind {
        /// A durable write landed: entry saved, reminder saved or completed, vehicle added.
        case success
        /// Declared for symmetry with the system's three-way vocabulary; no emitter yet. Wiring
        /// one is a product decision (which failures deserve a buzz), not a plumbing change.
        case warning
        /// A local, reversible acknowledgement — e.g. queueing an attachment for removal, which
        /// announces the INTENT, not a committed delete. Tactile ack is honest for that.
        case lightImpact
    }

    /// Monotonic per kind. `.sensoryFeedback(trigger:)` fires on a CHANGE, so two successes in a
    /// row must produce two distinct values — a Bool toggle or a re-assigned enum would swallow
    /// the second. One counter per kind so firing one never re-triggers another's observer.
    private(set) var successCount = 0
    private(set) var warningCount = 0
    private(set) var lightImpactCount = 0

    init() {}

    func fire(_ kind: Kind) {
        switch kind {
        case .success: successCount += 1
        case .warning: warningCount += 1
        case .lightImpact: lightImpactCount += 1
        }
    }

    func count(for kind: Kind) -> Int {
        switch kind {
        case .success: return successCount
        case .warning: return warningCount
        case .lightImpact: return lightImpactCount
        }
    }
}
