import Foundation
import Testing
@testable import Garage

/// Covers the data derivations behind the Stats charts, and specifically the empty case.
///
/// All three charts previously rendered a blank card when they had nothing to show: a `Chart` with
/// no marks draws a 220pt rectangle of white space with no axes and no message, and
/// `WearHistoryChart` drew a heading floating over nothing. That reads as a failed load rather than
/// "nothing here yet", and it is what put a blank card in the App Store screenshot.
@MainActor
struct StatsChartDataTests {
    /// Distinct calendar days, one per index. Every fixture below previously took the SAME default
    /// date, so no test could exercise date-keyed marks — two same-date fill-ups collided into one
    /// chart mark and the suite stayed green anyway.
    private static func day(_ index: Int) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + Double(index) * 86_400)
    }

    private func entry(
        type: EntryType,
        cost: Double? = nil,
        mpg: Double? = nil,
        date: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> FirestoreEntry {
        var details: [String: AnyCodable] = [:]
        if let mpg { details["calculatedMPG"] = AnyCodable(mpg) }
        return FirestoreEntry(
            id: UUID().uuidString, vehicleId: "v", userId: "u", entryType: type,
            entryDate: date, odometerReading: 100, cost: cost, isDiy: nil, shopName: nil,
            notes: nil, attachmentPaths: [], isResolved: nil, details: details,
            createdAt: nil, updatedAt: nil
        )
    }

    // MARK: - MPG

    @Test func mpgPointsAreEmpty_withNoEntries() {
        #expect(MPGTrendChart.fuelPoints(from: []).isEmpty)
    }

    /// The case that produced the blank card: entries exist, but none are fuel with a computed MPG.
    @Test func mpgPointsAreEmpty_whenNoFuelEntryCarriesMPG() {
        let entries = [
            entry(type: .maintenance, cost: 120, date: Self.day(0)),
            entry(type: .fuel, cost: 60, date: Self.day(1))   // fuel, but no calculatedMPG yet
        ]
        #expect(MPGTrendChart.fuelPoints(from: entries).isEmpty)
    }

    @Test func mpgPointsIncludeOnlyFuelEntriesWithAComputedValue() {
        let entries = [
            entry(type: .fuel, mpg: 24.5, date: Self.day(0)),
            entry(type: .fuel, date: Self.day(1)),                  // no MPG — excluded
            entry(type: .maintenance, mpg: 99, date: Self.day(2))   // not fuel — excluded
        ]
        let points = MPGTrendChart.fuelPoints(from: entries)
        #expect(points.count == 1)
        #expect(points.first?.value == 24.5)
    }

    /// Each point carries its own entry's date, in entry order — the chart's x-axis is only
    /// meaningful if the mapping is one-to-one.
    @Test func mpgPointsCarryEachEntrysOwnDate() {
        let entries = [
            entry(type: .fuel, mpg: 22.0, date: Self.day(0)),
            entry(type: .fuel, mpg: 31.5, date: Self.day(9))
        ]
        let points = MPGTrendChart.fuelPoints(from: entries)
        #expect(points.map(\.date) == [Self.day(0), Self.day(9)])
        #expect(points.map(\.value) == [22.0, 31.5])
    }

    /// The defect this pins: the chart used to key its marks by `\.date`, so two fill-ups on one
    /// calendar day (a splash-and-dash before a trip, then a full tank) collided and one of the
    /// two real data points was silently dropped. Identity must come from the ENTRY, not the day.
    @Test func mpgPointsKeepBothFillUpsRecordedOnTheSameDay() {
        let sameDay = Self.day(4)
        let entries = [
            entry(type: .fuel, mpg: 19.8, date: sameDay),
            entry(type: .fuel, mpg: 27.3, date: sameDay)
        ]
        let points = MPGTrendChart.fuelPoints(from: entries)
        #expect(points.count == 2)
        #expect(Set(points.map(\.id)).count == 2)
        #expect(points.map(\.value) == [19.8, 27.3])
    }

    // MARK: - Cost

    @Test func costGroupsAreEmpty_withNoEntries() {
        #expect(CostBreakdownChart.costGroups(from: []).isEmpty)
    }

    /// A category whose entries all have nil cost sums to zero. Plotted, it is a zero-height bar —
    /// visually identical to an empty chart while still widening the axis.
    @Test func costGroupsDropZeroTotals_ratherThanPlottingInvisibleBars() {
        let entries = [entry(type: .maintenance), entry(type: .fuel)]
        #expect(CostBreakdownChart.costGroups(from: entries).isEmpty)
    }

    @Test func costGroupsSumPerCategory() {
        let entries = [
            entry(type: .maintenance, cost: 100),
            entry(type: .maintenance, cost: 50),
            entry(type: .fuel, cost: 60)
        ]
        let groups = Dictionary(uniqueKeysWithValues:
            CostBreakdownChart.costGroups(from: entries).map { ($0.type, $0.value) })
        #expect(groups[EntryType.maintenance.displayName] == 150)
        #expect(groups[EntryType.fuel.displayName] == 60)
    }

    @Test func costGroupsMixZeroAndNonZero_keepingOnlyTheReal() {
        let entries = [
            entry(type: .maintenance, cost: 200),
            entry(type: .fuel)                    // zero total — dropped
        ]
        let groups = CostBreakdownChart.costGroups(from: entries)
        #expect(groups.count == 1)
        #expect(groups.first?.type == EntryType.maintenance.displayName)
    }

    /// Dictionary iteration order is not stable, so the same data could otherwise reorder bars
    /// between renders.
    @Test func costGroupOrderIsDeterministic() {
        let entries = [
            entry(type: .fuel, cost: 60),
            entry(type: .maintenance, cost: 100)
        ]
        let first = CostBreakdownChart.costGroups(from: entries).map(\.type)
        for _ in 0..<20 {
            #expect(CostBreakdownChart.costGroups(from: entries).map(\.type) == first)
        }
        #expect(first == first.sorted())
    }
}
