import Foundation
import Testing
@testable import Garage

/// The rating prompt is unusual in that the system silently caps it at three per user per year and
/// reports nothing back — so a prompt raised at a bad moment is not a cosmetic mistake, it is one
/// of three chances permanently spent. Every rule below exists to protect that budget.
struct ReviewPromptPolicyTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(
        score: Int, version: String? = nil, promptedAt: Date? = nil
    ) -> ReviewPromptState {
        ReviewPromptState(score: score, lastPromptedVersion: version, lastPromptedAt: promptedAt)
    }

    @Test func doesNotPromptBelowTheScoreThreshold() {
        let below = ReviewPromptPolicy.scoreRequired - 1
        #expect(!ReviewPromptPolicy.shouldPrompt(
            state: state(score: below), appVersion: "1.0", now: epoch
        ))
    }

    @Test func promptsOnceTheThresholdIsReachedAndNothingHasBeenAskedBefore() {
        #expect(ReviewPromptPolicy.shouldPrompt(
            state: state(score: ReviewPromptPolicy.scoreRequired), appVersion: "1.0", now: epoch
        ))
    }

    /// The whole first-run flow must not be able to earn a prompt: someone who has added a vehicle
    /// and logged exactly one entry has seen almost nothing of the app yet.
    @Test func aSingleFirstEntryCannotReachTheThreshold() {
        #expect(ReviewMoment.entryLogged.weight < ReviewPromptPolicy.scoreRequired)
    }

    @Test func doesNotPromptTwiceOnTheSameAppVersion() {
        let asked = state(score: 99, version: "1.0", promptedAt: epoch)
        #expect(!ReviewPromptPolicy.shouldPrompt(
            state: asked, appVersion: "1.0", now: epoch.addingTimeInterval(3650 * day)
        ))
    }

    @Test func doesNotPromptOnANewVersionInsideTheCooldown() {
        let asked = state(score: 99, version: "1.0", promptedAt: epoch)
        #expect(!ReviewPromptPolicy.shouldPrompt(
            state: asked, appVersion: "1.1", now: epoch.addingTimeInterval(30 * day)
        ))
    }

    @Test func promptsOnANewVersionAfterTheCooldown() {
        let asked = state(score: 99, version: "1.0", promptedAt: epoch)
        #expect(ReviewPromptPolicy.shouldPrompt(
            state: asked,
            appVersion: "1.1",
            now: epoch.addingTimeInterval(ReviewPromptPolicy.cooldown + 1)
        ))
    }

    /// A stored date in the future is only reachable via a device clock change. Treating it as
    /// "cooldown not yet satisfied" would lock the user out of ever being asked again.
    @Test func aFutureLastPromptedDateDoesNotLockTheUserOutForever() {
        let skewed = state(score: 99, version: "1.0", promptedAt: epoch.addingTimeInterval(500 * day))
        #expect(ReviewPromptPolicy.shouldPrompt(state: skewed, appVersion: "1.1", now: epoch))
    }
}

@MainActor
struct ReviewPromptStoreTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// `defaults: nil` keeps every test in-memory — a store bound to standard defaults would leak
    /// pacing state between tests and into the test host.
    private func store(version: String = "1.0", now: Date? = nil) -> ReviewPromptStore {
        let fixed = now ?? epoch
        return ReviewPromptStore(defaults: nil, appVersion: version, now: { fixed })
    }

    @Test func startsWithNoPromptDue() {
        #expect(!store().isPromptDue)
    }

    @Test func accumulatesWeightAcrossMomentsUntilDue() {
        let subject = store()
        subject.record(.entryLogged)
        #expect(!subject.isPromptDue)
        subject.record(.pdfExported)
        #expect(subject.isPromptDue)
    }

    @Test func oneExportAloneIsNotEnough() {
        let subject = store()
        subject.record(.pdfExported)
        #expect(!subject.isPromptDue)
    }

    /// The bug this guards: treating `requestReview` as if it reported success. It reports nothing,
    /// so if the score were not reset the app would re-ask on every subsequent value moment.
    @Test func markingPromptedClearsTheScoreAndTheDueFlag() {
        let subject = store()
        subject.record(.pdfExported)
        subject.record(.pdfExported)
        #expect(subject.isPromptDue)

        subject.markPrompted()
        #expect(!subject.isPromptDue)

        subject.record(.pdfExported)
        subject.record(.pdfExported)
        // Same version — the version rule holds even though the score is back above threshold.
        #expect(!subject.isPromptDue)
    }

    @Test func suppressionStopsAnAlreadyDuePromptFromFiring() {
        let subject = store()
        subject.record(.pdfExported)
        subject.record(.entryLogged)
        #expect(subject.isPromptDue)

        subject.suppressForSession()
        #expect(!subject.isPromptDue)
    }

    /// The realistic failure shape: a save fails, the user retries and it works. That success must
    /// not resurrect the prompt inside the same session.
    @Test func suppressionSurvivesLaterSuccessesInTheSameSession() {
        let subject = store()
        subject.suppressForSession()
        subject.record(.pdfExported)
        subject.record(.pdfExported)
        #expect(!subject.isPromptDue)
    }

    @Test func stateSurvivesRelaunchThroughDefaults() {
        let defaults = UserDefaults(suiteName: "garage.review-prompt.tests")
        defaults?.removePersistentDomain(forName: "garage.review-prompt.tests")
        defer { defaults?.removePersistentDomain(forName: "garage.review-prompt.tests") }

        let first = ReviewPromptStore(defaults: defaults, appVersion: "1.0", now: { self.epoch })
        first.record(.pdfExported)
        #expect(!first.isPromptDue)

        // Relaunch: a fresh store over the same defaults must not start the count over.
        let second = ReviewPromptStore(defaults: defaults, appVersion: "1.0", now: { self.epoch })
        second.record(.entryLogged)
        #expect(second.isPromptDue)
    }

    @Test func corruptStoredStateFailsOpenRatherThanCrashing() {
        let defaults = UserDefaults(suiteName: "garage.review-prompt.corrupt")
        defaults?.removePersistentDomain(forName: "garage.review-prompt.corrupt")
        defer { defaults?.removePersistentDomain(forName: "garage.review-prompt.corrupt") }
        defaults?.set(Data("not json".utf8), forKey: ReviewPromptStore.storageKey)

        let subject = ReviewPromptStore(defaults: defaults, appVersion: "1.0", now: { self.epoch })
        #expect(!subject.isPromptDue)
        subject.record(.pdfExported)
        subject.record(.entryLogged)
        #expect(subject.isPromptDue)
    }
}
