import Foundation
import Testing
@testable import Garage

/// Track days are the entries an enthusiast is proudest of, so a wrong count is noticed
/// immediately — and the venue count is the one figure here the owner cannot verify at a glance.
struct TrackDaySummaryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func trackDay(venue: String?, daysAgo: Double, id: String = UUID().uuidString) -> FirestoreEntry {
        FirestoreEntry(
            id: id, vehicleId: "v", userId: "u", entryType: .trackDay,
            entryDate: now.addingTimeInterval(-daysAgo * day), odometerReading: 0, cost: nil,
            isDiy: nil, shopName: nil, notes: nil, attachmentPaths: [], isResolved: nil,
            details: venue.map { ["venueName": AnyCodable($0)] } ?? [:],
            createdAt: nil, updatedAt: nil
        )
    }

    private func otherEntry(daysAgo: Double) -> FirestoreEntry {
        FirestoreEntry(
            id: UUID().uuidString, vehicleId: "v", userId: "u", entryType: .oilChange,
            entryDate: now.addingTimeInterval(-daysAgo * day), odometerReading: 0, cost: nil,
            isDiy: nil, shopName: nil, notes: nil, attachmentPaths: [], isResolved: nil,
            details: ["venueName": AnyCodable("Laguna Seca")], createdAt: nil, updatedAt: nil
        )
    }

    /// Most owners never take the car to a circuit. A card explaining a section they will never
    /// fill is noise on a screen that already has four.
    @Test func aVehicleWithNoTrackDaysHasNoCard() {
        #expect(TrackDaySummary.totals(for: []) == nil)
        #expect(TrackDaySummary.totals(for: [otherEntry(daysAgo: 1)]) == nil)
    }

    @Test func daysAndVenuesAreCounted() {
        let entries = [
            trackDay(venue: "Willow Springs", daysAgo: 10),
            trackDay(venue: "Laguna Seca", daysAgo: 40),
            trackDay(venue: "Willow Springs", daysAgo: 80)
        ]
        let totals = TrackDaySummary.totals(for: entries)
        #expect(totals?.days == 3)
        #expect(totals?.venues == 2)
    }

    /// "Willow Springs", "willow springs" and " Willow Springs " are one circuit. Counting them as
    /// three inflates the only figure on the card the owner cannot check by eye.
    @Test func venuesMatchCaseInsensitivelyAfterTrimming() {
        let entries = [
            trackDay(venue: "Willow Springs", daysAgo: 10),
            trackDay(venue: "willow springs", daysAgo: 40),
            trackDay(venue: "  Willow Springs  ", daysAgo: 80)
        ]
        let totals = TrackDaySummary.totals(for: entries)
        #expect(totals?.days == 3)
        #expect(totals?.venues == 1)
    }

    /// An entry whose venue was left blank still happened. It counts as a day and not as a venue —
    /// and an all-whitespace name is blank, not a distinct circuit.
    @Test func aTrackDayWithNoVenueStillCountsAsADay() {
        let entries = [
            trackDay(venue: nil, daysAgo: 10),
            trackDay(venue: "   ", daysAgo: 40),
            trackDay(venue: "Sonoma", daysAgo: 80)
        ]
        let totals = TrackDaySummary.totals(for: entries)
        #expect(totals?.days == 3)
        #expect(totals?.venues == 1)
    }

    @Test func everyVenueBlankLeavesAValidDayCountAndZeroVenues() {
        let totals = TrackDaySummary.totals(for: [trackDay(venue: nil, daysAgo: 10)])
        #expect(totals?.days == 1)
        #expect(totals?.venues == 0)
        #expect(totals?.mostRecentVenue == nil)
    }

    @Test func theMostRecentTrackDayIsReported() {
        let entries = [
            trackDay(venue: "Laguna Seca", daysAgo: 40),
            trackDay(venue: "Willow Springs", daysAgo: 10),
            trackDay(venue: "Sonoma", daysAgo: 80)
        ]
        let totals = TrackDaySummary.totals(for: entries)
        #expect(totals?.mostRecentVenue == "Willow Springs")
        #expect(totals?.mostRecentDate == now.addingTimeInterval(-10 * day))
    }

    /// The venue is echoed as typed (minus surrounding whitespace), not lower-cased — the
    /// normalization exists for counting, not for display.
    @Test func theMostRecentVenueKeepsItsOwnCasing() {
        let entries = [trackDay(venue: "  Willow Springs  ", daysAgo: 10)]
        #expect(TrackDaySummary.totals(for: entries)?.mostRecentVenue == "Willow Springs")
    }

    /// Two sessions logged on the same date is ordinary for a weekend event. Without the id
    /// tiebreak the "most recent" line could change between renders on identical data.
    @Test func sameDateTrackDaysResolveDeterministically() {
        let entries = [
            trackDay(venue: "Sonoma", daysAgo: 10, id: "a"),
            trackDay(venue: "Thunderhill", daysAgo: 10, id: "b")
        ]
        let first = TrackDaySummary.totals(for: entries)
        #expect(first?.mostRecentVenue == "Thunderhill")
        for _ in 0..<20 {
            #expect(TrackDaySummary.totals(for: entries.shuffled()) == first)
        }
    }

    /// Non-track entries never count, even when their details happen to carry a venue name.
    @Test func onlyTrackDayEntriesAreCounted() {
        let entries = [otherEntry(daysAgo: 1), trackDay(venue: "Sonoma", daysAgo: 10)]
        let totals = TrackDaySummary.totals(for: entries)
        #expect(totals?.days == 1)
        #expect(totals?.venues == 1)
        #expect(totals?.mostRecentVenue == "Sonoma")
    }

    /// `bestLapTime` is unconstrained free text and is deliberately never read: mis-parsing a lap
    /// record is precisely the error an enthusiast would notice, and the card is worth less than
    /// the trust it would cost.
    @Test func lapTimesAreNeverParsedIntoTheSummary() {
        let entry = FirestoreEntry(
            id: "lap", vehicleId: "v", userId: "u", entryType: .trackDay, entryDate: now,
            odometerReading: 0, cost: nil, isDiy: nil, shopName: nil, notes: nil,
            attachmentPaths: [], isResolved: nil,
            details: ["venueName": AnyCodable("Sonoma"), "bestLapTime": AnyCodable("not a time")],
            createdAt: nil, updatedAt: nil
        )
        let totals = TrackDaySummary.totals(for: [entry])
        #expect(totals?.days == 1)
        #expect(totals?.mostRecentVenue == "Sonoma")
    }
}
