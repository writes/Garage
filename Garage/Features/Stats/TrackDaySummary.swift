import Foundation

/// What the owner's track season actually looks like, from track-day entries the app already
/// stores but only ever played back one row at a time.
///
/// Track days are the entries an enthusiast is proudest of and the ones a resale buyer reads first,
/// and until now they existed only as individual rows in the log and lines in the dossier. "Six
/// days across three venues" is the sentence the owner would write themselves, and it is derivable
/// with no new field and no new fetch: Stats already walks the vehicle's WHOLE history, so these
/// counts are lifetime-correct rather than capped at a recent page.
///
/// ## What is deliberately not here
///
/// `bestLapTime` is free text — "1:34.821", "94.8", "1.34.8", "PB!" — with no format constraint at
/// the form. Parsing it to show a personal best would be right most of the time and confidently
/// wrong the rest, and a lap record is precisely the figure an enthusiast would notice being wrong.
/// A card that quietly omits it is trustworthy; one that guesses is not.
enum TrackDaySummary {
    struct Totals: Equatable, Sendable {
        let days: Int
        /// Distinct venues, matched case-insensitively after trimming — "Willow Springs" and
        /// "willow springs " are one circuit, and counting them as two would inflate the only
        /// figure here the owner cannot verify at a glance.
        let venues: Int
        /// Nil when the most recent track day recorded no venue name. The date still stands.
        let mostRecentVenue: String?
        let mostRecentDate: Date
    }

    /// Minimal `details` probe, same reasoning as `TireActionProbe`: `TrackDayEntry` has four
    /// non-optional fields, so full decoding drops any legacy or partial entry — and a dropped
    /// entry here means a track day the owner logged and the count silently forgot.
    private struct VenueProbe: Decodable { var venueName: String? }

    /// Nil when the vehicle has no track days at all. An owner who has never been to a circuit
    /// should not be shown an empty track card explaining what one would contain — Stats already
    /// has four sections, and a fifth reading "0 track days" is the app narrating its own absence.
    static func totals(for entries: [FirestoreEntry]) -> Totals? {
        let trackDays = entries.filter { $0.entryType == .trackDay }
        // Total order: two track days on one date is ordinary (a two-session weekend logged
        // together), and Swift's max(by:) over equal dates is not otherwise deterministic.
        guard let mostRecent = trackDays.max(by: { ($0.entryDate, $0.id) < ($1.entryDate, $1.id) })
        else { return nil }

        let venues = Set(trackDays.compactMap { Self.venue(of: $0)?.lowercased() })
        return Totals(
            days: trackDays.count,
            venues: venues.count,
            mostRecentVenue: Self.venue(of: mostRecent),
            mostRecentDate: mostRecent.entryDate
        )
    }

    /// The trimmed venue name as the owner typed it, or nil when the entry carries none. An
    /// all-whitespace name is nil rather than a distinct venue.
    private static func venue(of entry: FirestoreEntry) -> String? {
        let name = entry.decodedDetails(as: VenueProbe.self)?.venueName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return name
    }
}
