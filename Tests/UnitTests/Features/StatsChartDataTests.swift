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
            entry(type: .maintenance, cost: 120),
            entry(type: .fuel, cost: 60)          // fuel, but no calculatedMPG yet
        ]
        #expect(MPGTrendChart.fuelPoints(from: entries).isEmpty)
    }

    @Test func mpgPointsIncludeOnlyFuelEntriesWithAComputedValue() {
        let entries = [
            entry(type: .fuel, mpg: 24.5),
            entry(type: .fuel),                   // no MPG — excluded
            entry(type: .maintenance, mpg: 99)    // not fuel — excluded
        ]
        let points = MPGTrendChart.fuelPoints(from: entries)
        #expect(points.count == 1)
        #expect(points.first?.value == 24.5)
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
