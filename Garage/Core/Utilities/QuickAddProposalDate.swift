import Foundation

/// Parses the ISO-8601 `entryDate` a quick-add Cloud Function proposes.
///
/// Voice and receipt proposals are separate wire types that happen to carry the same optional
/// date field, and each carried a byte-identical copy of this parse. One shared implementation
/// instead: a fix or a format tolerance added here can no longer land on one quick-add path and
/// silently miss the other.
///
/// Two attempts on purpose — the server sends fractional seconds, but a proposal echoed back
/// without them must still parse rather than silently become "today". A value that parses as
/// neither falls back, because a wrong date the owner does not notice is worse than today's date,
/// which they will.
enum QuickAddProposalDate {
    static func resolve(_ isoString: String?, default fallback: Date) -> Date {
        guard let isoString else { return fallback }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: isoString)
            ?? ISO8601DateFormatter().date(from: isoString)
            ?? fallback
    }
}
