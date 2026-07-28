import Foundation

/// A moment where the user has just *received* value, and is therefore a fair time to ask for an
/// App Store rating.
///
/// Apple's guidance — and plain decency — is to ask after a good experience and never after an
/// error, never inside a first-run flow, and never adjacent to a request for money. The system
/// silently caps prompts at three per year per user, so a prompt spent at a weak moment is not
/// merely ignored: it is one of three chances gone until the next year.
///
/// Weighted rather than counted, because the moments are not equal. A finished PDF dossier is the
/// app's peak-value moment — it is the reason someone keeps a service log at all — while a single
/// logged entry is routine upkeep. Weighting asks the exporting user sooner than the user who has
/// merely typed once.
enum ReviewMoment: String, Codable, Sendable, CaseIterable {
    case entryLogged
    case oilAnalysisSucceeded
    case pdfExported

    var weight: Int {
        switch self {
        case .entryLogged: return 1
        case .oilAnalysisSucceeded: return 2
        case .pdfExported: return 3
        }
    }
}

/// Persisted across launches. Deliberately carries no identity: this is device-local pacing, not
/// user data, and it must survive sign-out (asking a returning user again on the same build would
/// waste one of the three annual prompts).
struct ReviewPromptState: Codable, Equatable, Sendable {
    var score = 0
    var lastPromptedVersion: String?
    var lastPromptedAt: Date?
}

/// Pure eligibility rules, split from the store so every branch is testable without UserDefaults,
/// a clock, or StoreKit.
enum ReviewPromptPolicy {
    /// One export plus one entry, one export plus one oil analysis, or four logged entries. Set so
    /// that no single first-run action can reach it: a brand-new user finishing the add-vehicle →
    /// add-first-entry flow scores 1 and is not asked.
    static let scoreRequired = 4

    /// Long enough that a user who ignored the prompt is not nagged in the same season, short
    /// enough that a genuinely long-lived user is asked again on a much later version.
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    static func shouldPrompt(state: ReviewPromptState, appVersion: String, now: Date) -> Bool {
        guard state.score >= scoreRequired else { return false }
        // Never twice on the same build. Someone who declined on this version has answered for
        // this version; the cooldown below governs the gap across versions.
        guard state.lastPromptedVersion != appVersion else { return false }
        guard let last = state.lastPromptedAt else { return true }

        let elapsed = now.timeIntervalSince(last)
        // A negative elapsed means the stored date is in the future — only reachable by a device
        // clock change. Treating that as "cooldown unsatisfied" would lock the user out of ever
        // being asked again, which is far worse than one extra prompt the system already caps.
        return elapsed >= cooldown || elapsed < 0
    }
}
