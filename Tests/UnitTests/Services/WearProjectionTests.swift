import Foundation
import Testing
@testable import Garage

/// A projection about when a brake pad runs out is the most consequential number the app derives.
/// Every test below is a case where the honest answer is silence — the happy path is the exception,
/// not the rule, and a regression that turns any of these into a figure is worse than a crash.
struct WearProjectionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        _ item: WearItemType = .frontBrakePads, pct: Double?, odometer: Int, daysAgo: Double
    ) -> WearSnapshot {
        WearSnapshot(
            id: UUID().uuidString, vehicleId: "v", entryId: nil, wearItem: item,
            valuePct: pct, valueRaw: nil, odometerReading: odometer,
            recordedAt: start.addingTimeInterval(-daysAgo * 24 * 60 * 60)
        )
    }

    private func miles(_ snapshots: [WearSnapshot], _ item: WearItemType = .frontBrakePads) -> Int? {
        WearProjection.milesToReplacement(for: item, from: snapshots)
    }

    // MARK: - The happy path

    /// 20 points across 4,000 miles is 0.005 %/mi; 60% remaining is 12,000 miles, which is already
    /// two significant figures.
    @Test func twoReadingsAcrossARealSpanProjectRemainingMiles() {
        let history = [
            snapshot(pct: 80, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(history) == 12_000)
    }

    /// The rate must come from the two NEWEST readings, not the outermost pair: a pad replaced and
    /// then bedded in wears at a different rate than the set it replaced.
    @Test func theTwoMostRecentReadingsSetTheRate() {
        let history = [
            snapshot(pct: 90, odometer: 10_000, daysAgo: 900),
            snapshot(pct: 80, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(history) == 12_000)
    }

    /// Only this item's own history counts. Rear pads wearing fast must not shorten the front
    /// projection.
    @Test func snapshotsForOtherItemsAreIgnored() {
        let history = [
            snapshot(.rearBrakePads, pct: 30, odometer: 43_900, daysAgo: 20),
            snapshot(pct: 80, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(history) == 12_000)
    }

    // MARK: - The guards, each of which must return nil

    @Test func oneReadingIsAPointNotARate() {
        #expect(miles([snapshot(pct: 60, odometer: 44_000, daysAgo: 10)]) == nil)
        #expect(miles([]) == nil)
    }

    /// A raw-only reading ("8/32 in") carries no percentage. It is skipped, not read as zero — and
    /// skipping it here leaves one usable reading, so there is still nothing to say.
    @Test func readingsWithoutAPercentageDoNotCount() {
        let history = [
            snapshot(pct: nil, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(history) == nil)
    }

    /// The percentage went UP, so the part was replaced between readings and the clock reset. The
    /// slope across a replacement is two different parts, not wear.
    @Test func aPercentageThatIncreasedMeansTheClockReset() {
        let history = [
            snapshot(pct: 40, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 90, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(history) == nil)
    }

    @Test func readingsTooCloseTogetherAreMeasurementNoiseNotWear() {
        let history = [
            snapshot(pct: 80, odometer: 43_900, daysAgo: 30),
            snapshot(pct: 60, odometer: 44_050, daysAgo: 10)
        ]
        #expect(miles(history) == nil)

        // The boundary itself qualifies: 200 miles exactly.
        let atBoundary = [
            snapshot(pct: 80, odometer: 43_800, daysAgo: 30),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(atBoundary) == 600)
    }

    /// Same odometer on both readings, or an out-of-order odometer correction — the span guard
    /// catches both, so nothing ever divides by zero or by a negative distance.
    @Test func aZeroOrBackwardsSpanYieldsNothing() {
        let same = [
            snapshot(pct: 80, odometer: 44_000, daysAgo: 30),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(same) == nil)

        let backwards = [
            snapshot(pct: 80, odometer: 44_000, daysAgo: 30),
            snapshot(pct: 60, odometer: 41_000, daysAgo: 10)
        ]
        #expect(miles(backwards) == nil)
    }

    /// An unchanged reading is a real event — a check that found no measurable wear — and it means
    /// the rate is zero, not that the part lasts forever.
    @Test func anUnchangedReadingIsNotInfiniteLife() {
        let history = [
            snapshot(pct: 60, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(history) == nil)
    }

    /// A barely-used part's remaining life is governed by how it will be driven, not by the sliver
    /// of wear seen so far. The threshold is exclusive: 95% is already too fresh.
    @Test func aFreshPartHasNoMeaningfulProjection() {
        let fresh = [
            snapshot(pct: 100, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 96, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(fresh) == nil)

        let atThreshold = [
            snapshot(pct: 100, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 95, odometer: 44_000, daysAgo: 10)
        ]
        #expect(miles(atThreshold) == nil)
    }

    /// Not one of the mandated guards, and it has to be here: a 1% drop across 5,000 miles clears
    /// every other check and projects past a million miles. Six-figure advice about a brake pad is
    /// the app visibly guessing.
    @Test func anAbsurdlyLongProjectionIsWithheldRatherThanPrinted() {
        let history = [
            snapshot(pct: 91, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 90, odometer: 45_000, daysAgo: 10)
        ]
        #expect(miles(history) == nil)
    }

    // MARK: - Rounding

    /// False precision reads as fabrication: the inputs are whole-percent readings, so the output
    /// cannot honestly carry four figures of resolution.
    @Test func projectionsRoundToTwoSignificantFigures() {
        #expect(WearProjection.roundedToTwoSignificantFigures(4_183) == 4_200)
        #expect(WearProjection.roundedToTwoSignificantFigures(823) == 820)
        #expect(WearProjection.roundedToTwoSignificantFigures(12_345) == 12_000)
        #expect(WearProjection.roundedToTwoSignificantFigures(996) == 1_000)
        #expect(WearProjection.roundedToTwoSignificantFigures(100) == 100)
        // Already at or below two figures — pass through rather than round to zero.
        #expect(WearProjection.roundedToTwoSignificantFigures(47) == 47)
        #expect(WearProjection.roundedToTwoSignificantFigures(7) == 7)
    }

    /// End to end: 14 points across 1,100 miles leaves 4,557 miles, which must reach the caller as
    /// 4,600. The raw figure is what a naive implementation would print.
    @Test func theProjectionItselfIsRounded() {
        let history = [
            snapshot(pct: 72, odometer: 43_000, daysAgo: 60),
            snapshot(pct: 58, odometer: 44_100, daysAgo: 10)
        ]
        #expect(miles(history) == 4_600)
    }

    // MARK: - The service that populates it

    @Test func theDashboardItemCarriesTheProjection() {
        let history = [
            snapshot(pct: 80, odometer: 40_000, daysAgo: 200),
            snapshot(pct: 60, odometer: 44_000, daysAgo: 10)
        ]
        let items = WearService.latestDashboardItems(from: history)
        #expect(items.count == 1)
        #expect(items.first?.milesToReplacement == 12_000)
    }

    @Test func theDashboardItemCarriesNilWhenTheHistoryCannotSupportAProjection() {
        let items = WearService.latestDashboardItems(from: [snapshot(pct: 60, odometer: 44_000, daysAgo: 10)])
        #expect(items.count == 1)
        #expect(items.first?.milesToReplacement == nil)
    }
}
