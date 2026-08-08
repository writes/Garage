import Testing
@testable import Garage

/// Demo `details` maps were hand-written, and three of the four did not decode as the struct their
/// own form saves and reads back: the track day carried `venue` where `TrackDayEntry` wants
/// `venueName` (Stats showed a track day with no track), the fill-up carried `mpg` where
/// `FuelEntry` wants `calculatedMPG` (the MPG chart skipped it), and brake carried free text where
/// enum raw values belong. Every one of those failed silently — `decodedDetails(as:)` returns nil
/// on a shape mismatch and callers read nil as "nothing to seed", never as an error. The seeds now
/// encode through `EntryFormViewModel.makeAnyCodableMap`, the same helper save() uses; these tests
/// are what stop the next hand-written map from getting in.
struct SeedDetailsCanonicalTests {
    @Test func trackDayDetails_decodeWithTheVenueStatsReadsBack() throws {
        let details = try #require(Self.seedEntry("seed-viper-track").decodedDetails(as: TrackDayEntry.self))

        #expect(details.venueName == "Willow Springs")
        #expect(details.eventType == .hpde)
        #expect(details.conditions == .dry)
        #expect(details.heatCyclesAdded == 1)
    }

    @Test func oilChangeDetails_decodeAsTheirCanonicalStruct() throws {
        let details = try #require(Self.seedEntry("seed-viper-oil").decodedDetails(as: OilChangeEntry.self))

        #expect(details.oilBrand == "Mobil 1")
        #expect(details.oilGrade == "0W-40")
        #expect(details.quantityQuarts == 10.5)
    }

    /// The old free text "Pads replaced / Fluid flush" is one canonical action plus the flag.
    @Test func brakeDetails_decodeAsTheirCanonicalStruct() throws {
        let details = try #require(Self.seedEntry("seed-viper-brake").decodedDetails(as: BrakeEntry.self))

        #expect(details.action == .padsReplaced)
        #expect(details.position == .all)
        #expect(details.fluidFlushed)
    }

    @Test func fuelDetails_decodeWithTheMPGTheTrendChartReadsBack() throws {
        let details = try #require(Self.seedEntry("seed-sq5-fuel").decodedDetails(as: FuelEntry.self))

        #expect(details.calculatedMPG == 19.6)
        #expect(details.fuelGrade == .premium91)
        #expect(details.totalCost == 74.15)
    }

    /// The class-closing case: a newly seeded entry with a hand-written map fails here rather than
    /// in a screen nobody re-checks. Unseeded entry types are recorded rather than skipped, so
    /// adding a seed of a new type has to add its canonical struct alongside it.
    @Test func everySeededDetailsMapDecodesAsItsCanonicalStruct() {
        for entry in Self.seededEntries where !entry.details.isEmpty {
            switch entry.entryType {
            case .trackDay: #expect(entry.decodedDetails(as: TrackDayEntry.self) != nil)
            case .oilChange: #expect(entry.decodedDetails(as: OilChangeEntry.self) != nil)
            case .brake: #expect(entry.decodedDetails(as: BrakeEntry.self) != nil)
            case .fuel: #expect(entry.decodedDetails(as: FuelEntry.self) != nil)
            default: Issue.record("Seeded \(entry.entryType) has details but no canonical type here")
            }
        }
    }

    private static var seededEntries: [FirestoreEntry] {
        SeedData.vehicles.flatMap { SeedData.entries(for: $0.id) }
    }

    private static func seedEntry(_ id: String) throws -> FirestoreEntry {
        try #require(seededEntries.first { $0.id == id })
    }
}
