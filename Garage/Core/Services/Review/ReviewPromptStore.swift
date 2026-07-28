import Foundation
import Observation

/// Accumulates value moments and decides when to hand StoreKit a rating request.
///
/// Separate from `AnalyticsService` on purpose. Routing this through analytics would have been
/// less code, but it would silently tie rating prompts to analytics consent — a user who declined
/// tracking would never be asked to rate, which is neither intended nor discoverable.
@MainActor
@Observable
final class ReviewPromptStore {
    static let storageKey = "garage.review-prompt.v1"

    static let shared = ReviewPromptStore(
        defaults: .standard,
        appVersion: Bundle.main.shortVersionString
    )

    private let defaults: UserDefaults?
    private let key: String
    private let appVersion: String
    private let now: () -> Date
    private var state: ReviewPromptState
    private var isSuppressedForSession = false

    /// Flips true the moment the user earns a prompt. A view observes this and performs the actual
    /// StoreKit request; the store itself never imports StoreKit, so it stays unit-testable.
    private(set) var isPromptDue = false

    /// `defaults: nil` gives a fully in-memory store — used by tests and by any non-production
    /// bootstrap mode, where writing rating pacing to the real domain would be wrong.
    init(
        defaults: UserDefaults?,
        key: String = storageKey,
        appVersion: String,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.appVersion = appVersion
        self.now = now

        // A corrupt or future-schema blob is discarded rather than migrated. The cost of being
        // wrong here is one extra rating prompt, so failing open beats carrying junk forward.
        if let data = defaults?.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ReviewPromptState.self, from: data) {
            state = decoded
        } else {
            state = ReviewPromptState()
        }
        refresh()
    }

    func record(_ moment: ReviewMoment) {
        guard !isSuppressedForSession else { return }
        state.score += moment.weight
        persist()
        refresh()
    }

    /// Call when the user hits a failure. The rest of the session is off-limits for rating asks:
    /// a user who just lost work, or watched a save fail, is not being asked to rate the app —
    /// and a prompt shown there is both rude and likely to earn one star.
    func suppressForSession() {
        isSuppressedForSession = true
        isPromptDue = false
    }

    /// The request has been handed to StoreKit. Whether the system actually rendered anything is
    /// deliberately unknowable — `requestReview` reports nothing back — so this counts the ask,
    /// not the impression, and resets the score either way. Assuming a silent no-op would let the
    /// app re-ask on every subsequent moment forever.
    func markPrompted() {
        state.lastPromptedVersion = appVersion
        state.lastPromptedAt = now()
        state.score = 0
        isPromptDue = false
        persist()
    }

    private func refresh() {
        guard !isSuppressedForSession else {
            isPromptDue = false
            return
        }
        isPromptDue = ReviewPromptPolicy.shouldPrompt(
            state: state, appVersion: appVersion, now: now()
        )
    }

    private func persist() {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

extension Bundle {
    /// `CFBundleShortVersionString` is the user-facing version ("1.0"), which is the granularity
    /// the prompt should pace against — a build-number bump inside one released version is not a
    /// new app from the user's point of view.
    var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
