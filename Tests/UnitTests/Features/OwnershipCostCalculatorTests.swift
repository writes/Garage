import Foundation
import Testing
@testable import Garage

/// Cost per mile is the first derived number the app produces rather than plays back. Every guard
/// below exists because the naive arithmetic is confidently wrong at the edges — and a wrong
/// ownership cost is worse than none, since it is the figure a resale buyer would be shown.
struct OwnershipCostCalculatorTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let month: TimeInterval = 30.44 * 24 * 60 * 60

    private func entry(cost: Double?, odometer: Int, daysAgo: Double = 0) -> FirestoreEntry {
        FirestoreEntry(
            id: UUID().uuidString, vehicleId: "v", userId: "u", entryType: .maintenance,
            entryDate: now.addingTimeInterval(-daysAgo * 24 * 60 * 60),
            odometerReading: odometer, cost: cost, isDiy: nil, shopName: nil, notes: nil,
            attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }

    @Test func noEntriesProducesNoSummary() {
        #expect(OwnershipCostCalculator.summary(for: [], now: now) == nil)
    }

    @Test func entriesWithoutAnyCostProduceNoSummary() {
        let entries = [entry(cost: nil, odometer: 1000), entry(cost: 0, odometer: 2000)]
        #expect(OwnershipCostCalculator.summary(for: entries, now: now) == nil)
    }

    @Test func costPerMileDividesTotalCostByDistanceCovered() {
        let entries = [
            entry(cost: 100, odometer: 10_000, daysAgo: 60),
            entry(cost: 200, odometer: 15_000, daysAgo: 0)
        ]
        let summary = OwnershipCostCalculator.summary(for: entries, now: now)
        #expect(summary?.totalCost == 300)
        #expect(summary?.milesCovered == 5_000)
        #expect(summary?.costPerMile == 0.06)
    }

    /// A free warranty repair still proves the car covered those miles. Counting it toward
    /// distance but not cost is what keeps cost per mile from being overstated.
    @Test func distanceCountsUncostedEntriesEvenThoughCostDoesNot() {
        let entries = [
            entry(cost: 300, odometer: 10_000, daysAgo: 60),
            entry(cost: nil, odometer: 20_000, daysAgo: 0)
        ]
        let summary = OwnershipCostCalculator.summary(for: entries, now: now)
        #expect(summary?.totalCost == 300)
        #expect(summary?.milesCovered == 10_000)
        #expect(summary?.costPerMile == 0.03)
    }

    /// Two entries at the same odometer is an ordinary day (service plus a fill-up), and the naive
    /// division there is infinity.
    @Test func sameOdometerOnEveryEntryYieldsNoCostPerMileRatherThanInfinity() {
        let entries = [
            entry(cost: 100, odometer: 10_000, daysAgo: 40),
            entry(cost: 100, odometer: 10_000, daysAgo: 0)
        ]
        let summary = OwnershipCostCalculator.summary(for: entries, now: now)
        #expect(summary?.costPerMile == nil)
        #expect(summary?.totalCost == 200)
    }

    @Test func aMissingOdometerReadingIsIgnoredRatherThanTreatedAsZeroMiles() {
        let entries = [
            entry(cost: 100, odometer: 0, daysAgo: 60),
            entry(cost: 100, odometer: 10_000, daysAgo: 30),
            entry(cost: 100, odometer: 12_000, daysAgo: 0)
        ]
        // A zero reading would otherwise make "miles covered" 12,000 instead of 2,000 and
        // understate cost per mile six-fold.
        #expect(OwnershipCostCalculator.summary(for: entries, now: now)?.milesCovered == 2_000)
    }

    @Test func costPerMonthDividesByTheSpanOfTheHistory() {
        let entries = [
            entry(cost: 600, odometer: 10_000, daysAgo: 30.44 * 6),
            entry(cost: 0, odometer: 16_000, daysAgo: 0)
        ]
        let perMonth = OwnershipCostCalculator.summary(for: entries, now: now)?.costPerMonth
        #expect(perMonth != nil)
        #expect(abs((perMonth ?? 0) - 100) < 0.01)
    }

    /// Annualising three days of ownership is arithmetically true and practically absurd.
    @Test func aHistoryShorterThanAMonthReportsNoMonthlyRate() {
        let entries = [
            entry(cost: 500, odometer: 10_000, daysAgo: 3),
            entry(cost: 100, odometer: 10_200, daysAgo: 0)
        ]
        let summary = OwnershipCostCalculator.summary(for: entries, now: now)
        #expect(summary?.costPerMonth == nil)
        // The per-mile figure is still sound over a short window, so it is still reported.
        #expect(summary?.costPerMile == 3)
    }

    @Test func aSingleCostedEntryStillReportsTotalButNeitherRate() {
        let summary = OwnershipCostCalculator.summary(for: [entry(cost: 250, odometer: 10_000)], now: now)
        #expect(summary?.totalCost == 250)
        #expect(summary?.costPerMile == nil)
        #expect(summary?.costPerMonth == nil)
    }
}
