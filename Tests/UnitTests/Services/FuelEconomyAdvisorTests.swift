import Foundation
import Testing
@testable import Garage

/// The averaging rule is the feature. A mean of per-tank MPG figures weights a four-gallon
/// splash-and-dash exactly as heavily as a twenty-gallon fill, which can both hide a real drop and
/// invent one — so the unequal-tank tests below are the ones that matter most.
struct FuelEconomyAdvisorTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    /// `daysAgo` orders the window; index 0 is the newest fill-up.
    private func fuel(mpg: Double?, gallons: Double?, daysAgo: Double) -> FirestoreEntry {
        var details: [String: AnyCodable] = [:]
        if let mpg { details["calculatedMPG"] = AnyCodable(mpg) }
        if let gallons { details["gallons"] = AnyCodable(gallons) }
        return FirestoreEntry(
            id: UUID().uuidString, vehicleId: "v", userId: "u", entryType: .fuel,
            entryDate: now.addingTimeInterval(-daysAgo * day), odometerReading: 0, cost: nil,
            isDiy: nil, shopName: nil, notes: nil, attachmentPaths: [], isResolved: nil,
            details: details, createdAt: nil, updatedAt: nil
        )
    }

    /// `recent` newest first, then `older` — enough to fill the ten-tank baseline.
    private func history(recent: [Double], older: [Double], gallons: Double = 10) -> [FirestoreEntry] {
        (recent + older).enumerated().map { index, mpg in
            fuel(mpg: mpg, gallons: gallons, daysAgo: Double(index) * 7)
        }
    }

    // MARK: - Having enough to speak at all

    /// Nine fill-ups is not a baseline. Telling an owner their engine is sick on the strength of a
    /// partial window is how a diagnostic surface loses the only thing it has.
    @Test func fewerThanTenFillUpsProduceNoVerdict() {
        let nine = history(recent: [16, 16, 16], older: Array(repeating: 30.0, count: 6))
        #expect(nine.count == 9)
        #expect(FuelEconomyAdvisor.degradation(in: nine) == nil)
    }

    @Test func noFuelHistoryAtAllProducesNoVerdict() {
        #expect(FuelEconomyAdvisor.degradation(in: []) == nil)
    }

    /// A fill-up missing either figure cannot be weighted honestly, so it leaves the window
    /// entirely — which here drops the count below the baseline and yields silence.
    @Test func fillUpsMissingMPGOrGallonsAreExcludedFromTheWindow() {
        var entries = history(recent: [16, 16, 16], older: Array(repeating: 30.0, count: 7))
        entries.append(fuel(mpg: nil, gallons: 12, daysAgo: 100))
        entries.append(fuel(mpg: 28, gallons: nil, daysAgo: 107))
        entries.append(fuel(mpg: 28, gallons: 0, daysAgo: 114))
        entries.append(fuel(mpg: 0, gallons: 12, daysAgo: 121))
        #expect(FuelEconomyAdvisor.degradation(in: entries)?.currentAvgMPG == 16)

        let onlyPartial = Array(entries.suffix(4))
        #expect(FuelEconomyAdvisor.degradation(in: onlyPartial) == nil)
    }

    /// Non-fuel entries share the feed and must not be counted as tanks.
    @Test func nonFuelEntriesAreNotTanks() {
        let service = FirestoreEntry(
            id: "s", vehicleId: "v", userId: "u", entryType: .oilChange, entryDate: now,
            odometerReading: 0, cost: nil, isDiy: nil, shopName: nil, notes: nil,
            attachmentPaths: [], isResolved: nil,
            details: ["calculatedMPG": AnyCodable(4.0), "gallons": AnyCodable(10.0)],
            createdAt: nil, updatedAt: nil
        )
        let entries = [service] + history(recent: [30, 30, 30], older: Array(repeating: 30.0, count: 6))
        #expect(FuelEconomyAdvisor.degradation(in: entries) == nil)
    }

    // MARK: - The threshold

    /// Ten equal tanks, the newest three at 11.9 MPG against seven at 14.9: the baseline is
    /// (3 × 11.9 + 7 × 14.9) / 10 = 14.0, so the drop is exactly 15.0%. The threshold is
    /// EXCLUSIVE, because a flag that fires at the seasonal boundary fires every autumn.
    @Test func aDropOfExactlyFifteenPercentDoesNotFlag() {
        let entries = history(recent: [11.9, 11.9, 11.9], older: Array(repeating: 14.9, count: 7))
        #expect(FuelEconomyAdvisor.degradation(in: entries) == nil)
    }

    /// One tenth of an MPG below the boundary case above is enough to cross it — 15.5%.
    @Test func aDropJustPastFifteenPercentFlags() {
        let entries = history(recent: [11.8, 11.8, 11.8], older: Array(repeating: 14.9, count: 7))
        #expect(FuelEconomyAdvisor.degradation(in: entries) != nil)
    }

    @Test func aDropPastFifteenPercentFlags() {
        let entries = history(recent: [20, 20, 20], older: Array(repeating: 30.0, count: 7))
        let verdict = FuelEconomyAdvisor.degradation(in: entries)
        #expect(verdict != nil)
        #expect(verdict?.currentAvgMPG == 20)
        // The baseline INCLUDES the recent three by design: (3*20 + 7*30) / 10 = 27.
        #expect(verdict?.baselineAvgMPG == 27)
        // (27 - 20) / 27 = 25.9%.
        #expect(((verdict?.dropPct ?? 0) - 25.925).magnitude < 0.01)
    }

    @Test func steadyEconomyProducesNoVerdict() {
        let entries = history(recent: [28, 30, 29], older: Array(repeating: 29.0, count: 7))
        #expect(FuelEconomyAdvisor.degradation(in: entries) == nil)
    }

    /// Improving economy is not a drop. `dropPct` going negative must never satisfy the threshold.
    @Test func improvingEconomyProducesNoVerdict() {
        let entries = history(recent: [40, 40, 40], older: Array(repeating: 25.0, count: 7))
        #expect(FuelEconomyAdvisor.degradation(in: entries) == nil)
    }

    // MARK: - The aggregation itself

    /// The pin. Two 20-gallon tanks at 10 MPG and one 2-gallon splash at 40 MPG:
    ///   correct  — (200 + 200 + 80) miles / 42 gallons = 11.4 MPG
    ///   WRONG    — (10 + 10 + 40) / 3 = 20 MPG, nearly double, from a tank worth 5% of the fuel.
    /// Getting this wrong silently hides genuine degradation behind one short top-up.
    @Test func theWindowAverageIsTotalMilesOverTotalGallonsNotTheMeanOfPerTankMPG() {
        let recent = [
            fuel(mpg: 40, gallons: 2, daysAgo: 0),
            fuel(mpg: 10, gallons: 20, daysAgo: 7),
            fuel(mpg: 10, gallons: 20, daysAgo: 14)
        ]
        let baseline = (0..<7).map { fuel(mpg: 20, gallons: 20, daysAgo: Double(21 + $0 * 7)) }
        let verdict = FuelEconomyAdvisor.degradation(in: recent + baseline)

        let expectedCurrent = 480.0 / 42.0
        #expect(((verdict?.currentAvgMPG ?? 0) - expectedCurrent).magnitude < 0.0001)
        #expect((verdict?.currentAvgMPG ?? 0) < 12)

        // Baseline over all ten: (480 + 7 * 400) miles / (42 + 140) gallons.
        let expectedBaseline = 3_280.0 / 182.0
        #expect(((verdict?.baselineAvgMPG ?? 0) - expectedBaseline).magnitude < 0.0001)
    }

    /// The mirror: a large efficient tank must not be diluted by a tiny inefficient one. A
    /// mean-of-means here would read 15 MPG and flag a car that is fine.
    @Test func aTinyInefficientTankCannotManufactureADrop() {
        let recent = [
            fuel(mpg: 5, gallons: 1, daysAgo: 0),
            fuel(mpg: 25, gallons: 20, daysAgo: 7),
            fuel(mpg: 25, gallons: 20, daysAgo: 14)
        ]
        let baseline = (0..<7).map { fuel(mpg: 25, gallons: 20, daysAgo: Double(21 + $0 * 7)) }
        #expect(FuelEconomyAdvisor.degradation(in: recent + baseline) == nil)
    }

    /// Order in, order out: the caller's array arrives newest-first from the feed, but nothing may
    /// depend on that. Reversed and shuffled inputs must produce the same verdict.
    @Test func theWindowIsChosenByDateNotByArrayOrder() {
        let entries = history(recent: [20, 20, 20], older: Array(repeating: 30.0, count: 7))
        let forwards = FuelEconomyAdvisor.degradation(in: entries)
        let backwards = FuelEconomyAdvisor.degradation(in: entries.reversed())
        #expect(forwards == backwards)
        #expect(forwards?.currentAvgMPG == 20)
    }

    /// Two fill-ups on the same day are ordinary. Swift's sort is not stable, so without the id
    /// tiebreak the window's membership could change between runs on identical data.
    @Test func sameDayFillUpsProduceADeterministicWindow() {
        // FOUR same-day tanks with DISTINCT values contending for a 3-tank window: identical
        // fixtures would average the same under any subset, letting an unstable sort pass this
        // test forever (cross-check finding). With distinct values, dropping the id tiebreak
        // makes the window's membership — and therefore the average — vary across shuffles.
        var entries = [
            fuel(mpg: 14, gallons: 12, daysAgo: 0),
            fuel(mpg: 16, gallons: 10, daysAgo: 0),
            fuel(mpg: 18, gallons: 8, daysAgo: 0),
            fuel(mpg: 20, gallons: 14, daysAgo: 0)
        ]
        entries += (0..<7).map { fuel(mpg: 30, gallons: 10, daysAgo: Double(7 + $0 * 7)) }
        let first = FuelEconomyAdvisor.degradation(in: entries)
        #expect(first != nil)
        for _ in 0..<20 {
            #expect(FuelEconomyAdvisor.degradation(in: entries.shuffled()) == first)
        }
    }
}
