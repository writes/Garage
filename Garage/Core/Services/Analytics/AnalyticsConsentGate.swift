import Foundation

/// Decides whether an event is sent now, held, or dropped — and holds pre-consent events until
/// consent is actually known.
///
/// WHY THIS EXISTS. Consent is not knowable until the user profile loads, and the profile cannot
/// load until the user has signed in. Under a plain `guard isEnabled` gate that makes the entire
/// sign-in funnel unobservable: every `sign_in_*` event fires while the gate is still closed and
/// is silently dropped. That is exactly what shipped on 2026-07-27 and had to be repaired.
///
/// The rule is *not* "buffer while disabled". `setEnabled(false)` is overloaded in this app — it
/// means both "consent is not known yet" (app start, bootstrap, auth-state change) and "this
/// identity is finished" (sign-out, profile/uid mismatch). Holding events across the second kind
/// would let one account's events flush into another account's consent, which is a privacy defect
/// strictly worse than the missing funnel. So identity changes call `discardPending()` explicitly
/// and the two meanings stay separate.
///
/// Pure value type on purpose: the real gate is unit-testable without Firebase, which is the hole
/// that let the original defect through — the old test spy recorded unconditionally and could
/// never have caught it.
struct AnalyticsConsentGate {
    /// Held events are capped so a user who never reaches consent cannot grow memory without
    /// bound. The sign-in funnel is a handful of events; anything beyond this is a bug, and the
    /// OLDEST is dropped so the most recent context survives.
    static let defaultLimit = 32

    private(set) var isEnabled = false
    private var isSuppressedForSession = false
    private var pending: [AnalyticsEvent] = []
    /// Held user-property sets, keyed by property name — LATEST value per property wins, unlike
    /// events, because a property is state, not an occurrence. Unbounded growth is impossible:
    /// the key space is the closed `UserProperty` name set.
    private var pendingProperties: [String: UserProperty] = [:]
    private let limit: Int

    init(limit: Int = defaultLimit) {
        self.limit = limit
    }

    /// Events currently held awaiting a consent decision. Exposed for tests and diagnostics.
    var pendingCount: Int { pending.count }

    /// Property sets currently held awaiting a consent decision. Exposed for tests.
    var pendingPropertyCount: Int { pendingProperties.count }

    /// Returns the events to send right now — empty when the event was held instead.
    mutating func track(_ event: AnalyticsEvent) -> [AnalyticsEvent] {
        if isEnabled { return [event] }
        // A session-suppressed user has affirmatively revoked; never accumulate for them.
        guard !isSuppressedForSession else { return [] }
        pending.append(event)
        if pending.count > limit { pending.removeFirst(pending.count - limit) }
        return []
    }

    /// Returns the property sets to apply right now — empty when held. Same consent semantics
    /// as `track`: user properties attach to every future event, so a pre-consent set reaching
    /// Firebase would be exactly the leak the event gate exists to prevent.
    mutating func setUserProperty(_ property: UserProperty) -> [UserProperty] {
        if isEnabled { return [property] }
        guard !isSuppressedForSession else { return [] }
        pendingProperties[property.name] = property
        return []
    }

    /// Returns any held events released by this transition.
    ///
    /// Enabling is the ONLY affirmative consent signal, so it is the only thing that releases the
    /// buffer. Disabling deliberately keeps it: at that point consent is merely unknown, and the
    /// events are still unsent and still on-device.
    mutating func setEnabled(_ enabled: Bool) -> [AnalyticsEvent] {
        setEnabledReleasingHeld(enabled).events
    }

    /// `setEnabled` variant that also releases held user properties. The caller must apply the
    /// properties BEFORE logging the events so the flushed events carry them.
    mutating func setEnabledReleasingHeld(_ enabled: Bool) -> (events: [AnalyticsEvent], properties: [UserProperty]) {
        let effective = enabled && !isSuppressedForSession
        isEnabled = effective
        guard effective else { return ([], []) }
        let releasedEvents = pending
        pending.removeAll()
        // Sorted for deterministic application order (and testability); latest-per-name already
        // collapsed at hold time.
        let releasedProperties = pendingProperties.keys.sorted().compactMap { pendingProperties[$0] }
        pendingProperties.removeAll()
        return (releasedEvents, releasedProperties)
    }

    /// Drop everything held. Call when the identity these events belong to is gone — sign-out, or
    /// a profile that does not match the signed-in uid.
    mutating func discardPending() {
        pending.removeAll()
        pendingProperties.removeAll()
    }

    /// Fail-closed revocation for the rest of the session. Drops held events and stops collecting
    /// new ones, so a revocation that persistence could not confirm cannot leak retroactively.
    mutating func suppressForSession() {
        isSuppressedForSession = true
        isEnabled = false
        pending.removeAll()
        pendingProperties.removeAll()
    }
}
