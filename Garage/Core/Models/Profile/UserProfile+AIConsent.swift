import Foundation

/// Wire encoding for the AI-consent grant timestamp.
///
/// `ProfileFieldValue` carries only strings and booleans (the Firestore profile map is
/// deliberately narrow), so the grant is stored as an ISO-8601 string. The empty string is the
/// REVOKED representation: a partial write can clear consent without deleting the key, and a
/// full-profile save that carries a nil grant writes the same empty string rather than dropping
/// the field — the themeID convention, so both fields behave identically under `profileFields`.
extension UserProfile {
    static let aiConsentFieldKey = "aiConsentGrantedAt"

    /// A value that cannot be parsed reads as NOT granted — the fail-safe direction: the worst
    /// case is one extra prompt, never an unconsented upload.
    static func decodeAIConsent(_ value: ProfileFieldValue?) -> Date? {
        guard let raw = value?.stringValue, !raw.isEmpty else { return nil }
        return aiConsentFormatter().date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func encodeAIConsent(_ date: Date?) -> String {
        guard let date else { return "" }
        return aiConsentFormatter().string(from: date)
    }

    /// Built per call rather than cached: ISO8601DateFormatter is not Sendable, so a shared static
    /// one cannot exist under strict concurrency without an isolation claim this does not need.
    /// Fractional seconds stay off so the stored instant is readable in the Firestore console;
    /// consent is only ever compared against nil, never ordered.
    private static func aiConsentFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
