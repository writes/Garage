import Foundation

/// Account-level consent for the AI features that upload user content to Anthropic's Claude API
/// (App Review 5.1.2(i)). Voice quick-add sends the dictated transcript and receipt scan sends the
/// photographed/imported pages; both are gated on the grant recorded here.
///
/// Oil-analysis is deliberately NOT routed through this gate: it already asks per document
/// (`OilAnalysisConsentSheet`), and stacking a second sheet in front of it would double-gate the
/// one flow that is already stricter than the rule.
///
/// AppState — not a per-screen ProfileViewModel — owns this because the two gated surfaces are
/// sheets that can be opened before any profile screen ever loads, and both must read the same
/// answer as the Settings row.
extension AppState {
    var aiConsentGrantedAt: Date? { userProfile?.aiConsentGrantedAt }

    var hasGrantedAIConsent: Bool { aiConsentGrantedAt != nil }

    /// Writes ONLY the consent field (the `ProfileViewModel.setThemeID` partial-write precedent),
    /// so untouched profile fields survive. Applies locally first — the parked action proceeds
    /// without waiting on the network — and rolls the local profile back on failure or on an
    /// account switch mid-write.
    ///
    /// Returns false when nothing was persisted. A caller that has just collected an explicit
    /// Continue still proceeds: the tap IS the consent, and an unrecorded grant simply means the
    /// prompt appears again next time (fail-safe, never fail-open).
    @discardableResult
    func setAIConsentGranted(_ granted: Bool, now: Date = .now) async -> Bool {
        guard let expectedUserID = currentUserID else { return false }
        // Field-level rollback (the `rollBackTheme` precedent), never a whole-profile restore: a
        // snapshot of the entire profile taken before the await would clobber any edit that
        // landed DURING the write — a saved policy number would vanish because a consent write
        // timed out.
        let previousGrantedAt = userProfile?.aiConsentGrantedAt
        let grantedAt: Date? = granted ? now : nil
        applyAIConsentLocally(grantedAt)

        do {
            try await profileStore.saveProfileFields(
                [UserProfile.aiConsentFieldKey: .string(UserProfile.encodeAIConsent(grantedAt))],
                uid: expectedUserID
            )
            guard currentUserID == expectedUserID else {
                // Account switched mid-write: `userProfile` is already the NEW account's (or nil),
                // so there is nothing to roll back — restoring the old account's value here would
                // stamp it onto the wrong profile. The write itself was keyed to the old uid.
                return false
            }
            return true
        } catch {
            applyAIConsentLocally(previousGrantedAt)
            AppLogger.shared.error("AI consent write failed: \(error.localizedDescription)")
            return false
        }
    }

    /// No-ops when the profile has not loaded (offline first launch, failed bootstrap): there is no
    /// document to mutate, and synthesizing one here would let an empty profile overwrite the real
    /// one on the next full save. The server write above still lands, so the grant is picked up on
    /// the next load.
    private func applyAIConsentLocally(_ grantedAt: Date?) {
        guard var profile = userProfile else { return }
        profile.aiConsentGrantedAt = grantedAt
        userProfile = profile
    }
}
