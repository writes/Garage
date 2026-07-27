import Foundation
import Testing
@testable import Garage

/// Regression cover for the defect where the entire sign-in funnel was silently dropped.
///
/// The original gate was `guard isEnabled else { return }`, and `isEnabled` only becomes true when
/// the user profile loads — which happens AFTER sign-in. So every `sign_in_*` event was discarded
/// in production while the unit tests passed, because the test spy recorded unconditionally and
/// the real gate was only reachable through a Firebase-backed class no test exercised.
///
/// `AnalyticsConsentGate` is a pure value type specifically so that gap cannot reopen.
@MainActor
struct AnalyticsConsentGateTests {
    private let apple = AnalyticsEvent.signInStarted(provider: .apple)
    private let done = AnalyticsEvent.signInCompleted(provider: .apple)

    // MARK: - The defect this exists to prevent

    /// The exact production sequence. Before the fix this released nothing.
    @Test func signInEventsSurviveUntilConsentIsKnown() {
        var gate = AnalyticsConsentGate()

        // App start / bootstrap: fail closed, consent unknown.
        #expect(gate.setEnabled(false).isEmpty)

        // User taps sign in.
        #expect(gate.track(apple).isEmpty, "held, not sent — consent is not known yet")

        // Firebase auth-state change fires mid-flow and disables again. This is the step that
        // used to destroy the funnel.
        #expect(gate.setEnabled(false).isEmpty)

        #expect(gate.track(done).isEmpty)
        #expect(gate.pendingCount == 2)

        // Profile finally loads and the user has not opted out.
        let released = gate.setEnabled(true)
        #expect(released == [apple, done], "both sign-in events must survive, in order")
        #expect(gate.pendingCount == 0)
    }

    @Test func onceEnabled_eventsPassStraightThrough() {
        var gate = AnalyticsConsentGate()
        _ = gate.setEnabled(true)
        #expect(gate.track(apple) == [apple])
        #expect(gate.pendingCount == 0)
    }

    // MARK: - Consent denial

    /// An opted-out user must never have held events released. They stay on device, unsent.
    @Test func optedOutUser_neverReleasesHeldEvents() {
        var gate = AnalyticsConsentGate()
        _ = gate.track(apple)
        _ = gate.track(done)
        #expect(gate.setEnabled(false).isEmpty, "disabling must never release")
        #expect(!gate.isEnabled)
    }

    @Test func disablingKeepsEventsHeld_becauseConsentIsMerelyUnknown() {
        var gate = AnalyticsConsentGate()
        _ = gate.track(apple)
        _ = gate.setEnabled(false)
        #expect(gate.pendingCount == 1, "still on device, still unsent")
    }

    // MARK: - Identity separation (the privacy requirement)

    /// The reason `discardPending()` exists at all: without it, user A's pre-consent events would
    /// flush the moment user B consents.
    @Test func signOutDiscards_soOneAccountCannotFlushIntoAnother() {
        var gate = AnalyticsConsentGate()
        _ = gate.track(apple)
        #expect(gate.pendingCount == 1)

        gate.discardPending()
        #expect(gate.pendingCount == 0)

        #expect(gate.setEnabled(true).isEmpty, "the next account must inherit nothing")
    }

    @Test func discardThenTrack_stillWorksForTheNewIdentity() {
        var gate = AnalyticsConsentGate()
        _ = gate.track(apple)
        gate.discardPending()
        _ = gate.track(done)
        #expect(gate.setEnabled(true) == [done])
    }

    // MARK: - Session suppression (fail-closed revocation)

    @Test func suppression_dropsHeldEventsAndBlocksFurtherCollection() {
        var gate = AnalyticsConsentGate()
        _ = gate.track(apple)
        gate.suppressForSession()
        #expect(gate.pendingCount == 0)
        #expect(!gate.isEnabled)

        #expect(gate.track(done).isEmpty, "suppressed sessions must not accumulate")
        #expect(gate.pendingCount == 0)
    }

    @Test func suppression_cannotBeUndoneBySetEnabled() {
        var gate = AnalyticsConsentGate()
        gate.suppressForSession()
        #expect(gate.setEnabled(true).isEmpty)
        #expect(!gate.isEnabled, "a fail-closed revocation must outlast a later enable")
    }

    // MARK: - Bounded memory

    @Test func heldEventsAreCapped_droppingOldestSoRecentContextSurvives() {
        var gate = AnalyticsConsentGate(limit: 3)
        let events: [AnalyticsEvent] = [
            .formOpened(form: .vehicle),
            .formOpened(form: .entry),
            .formOpened(form: .export),
            .formOpened(form: .voiceQuickAdd)
        ]
        for event in events { _ = gate.track(event) }
        #expect(gate.pendingCount == 3)
        #expect(gate.setEnabled(true) == Array(events.suffix(3)), "oldest dropped, newest kept")
    }

    @Test func defaultLimitIsSmall_becauseTheFunnelIsAHandfulOfEvents() {
        #expect(AnalyticsConsentGate.defaultLimit == 32)
    }

    @Test func aGateThatNeverReachesConsent_doesNotGrowWithoutBound() {
        var gate = AnalyticsConsentGate(limit: 4)
        for _ in 0..<500 { _ = gate.track(apple) }
        #expect(gate.pendingCount == 4)
    }
}
