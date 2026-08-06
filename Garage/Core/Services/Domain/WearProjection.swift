import Foundation

/// Turns a wear item's snapshot history into "how much further this part goes".
///
/// The snapshots have always carried both halves of a slope — a percentage and the odometer it was
/// read at — and `WearService.latestDashboardItems` threw the slope away by collapsing to the
/// newest reading per item. A bar showing "Front Brake Pads 58%" is a fact the owner already typed
/// in; "≈ 4,200 mi left at current rate" is the thing they cannot work out from the bar.
///
/// ## Nil is the ordinary answer
///
/// Every guard below returns nil rather than a number, because this is a claim about when a safety
/// part runs out. A confident-looking figure extrapolated from two readings forty miles apart is
/// worse than no figure at all: the owner cannot tell the two apart, and only one of them plans a
/// brake job around it. `OwnershipCostCalculator` set the precedent — say nothing until the data
/// supports speech.
///
/// Pure and dependency-free so every rule is testable without Firestore or a view.
enum WearProjection {
    /// Below this the two readings are too close together for the slope to mean anything. Pad and
    /// tread measurements are recorded in whole percents and 32nds, so inside 200 miles most of the
    /// difference between two readings is measurement resolution rather than wear.
    static let minimumSpanMiles = 200

    /// A part this fresh has no useful projection. The remaining life of a barely-bedded pad is
    /// governed by how it will be driven, not by the sliver of wear observed so far, and
    /// extrapolating from that sliver produces figures in the hundreds of thousands of miles.
    static let freshPartThresholdPct = 95.0

    /// Past this the output is arithmetic, not advice: no brake pad, tire or clutch has a credible
    /// six-figure projection, and printing one tells the owner the app is guessing.
    ///
    /// NOT one of the originally specified guards — added because `minimumSpanMiles` alone does not
    /// exclude it. A 1% drop across 5,000 miles clears every other guard and projects past a
    /// million miles.
    static let credibleCeilingMiles = 100_000

    /// Miles until `item` reaches 0%, taken from its two most recent readings that carry a
    /// percentage. `snapshots` may be the whole vehicle's history — this filters to `item` itself.
    ///
    /// Snapshots with no `valuePct` are raw-only readings ("8/32 in", "worn on the inner edge").
    /// They carry no value to take a slope from, so they are skipped rather than read as zero,
    /// which would invent a cliff that never happened.
    static func milesToReplacement(for item: WearItemType, from snapshots: [WearSnapshot]) -> Int? {
        let readings = snapshots
            .filter { $0.wearItem == item && $0.valuePct != nil }
            .sorted { $0.recordedAt > $1.recordedAt }
        // One reading is a point, not a rate. Nothing to say.
        guard readings.count >= 2,
              let current = readings[0].valuePct,
              let previous = readings[1].valuePct else { return nil }

        // See `freshPartThresholdPct`.
        guard current < freshPartThresholdPct else { return nil }

        // The percentage went UP, so the part was replaced between the two readings and the clock
        // reset. A slope taken across a replacement is not wear — it is two different parts.
        guard current <= previous else { return nil }

        let span = readings[0].odometerReading - readings[1].odometerReading
        // Also catches a zero or negative span: two readings logged at the same odometer, or an
        // out-of-order odometer correction.
        guard span >= Self.minimumSpanMiles else { return nil }

        // Zero when the two readings are identical: real (a check that found no measurable change),
        // and dividing by it would claim infinite life.
        let ratePctPerMile = (previous - current) / Double(span)
        guard ratePctPerMile > 0 else { return nil }

        let remaining = current / ratePctPerMile
        guard remaining.isFinite, remaining >= 1 else { return nil }
        let miles = Int(remaining.rounded())
        guard miles <= Self.credibleCeilingMiles else { return nil }
        return Self.roundedToTwoSignificantFigures(miles)
    }

    /// Two significant figures, always. "4,183 miles left" claims a precision two readings cannot
    /// support, and false precision reads as fabrication — "≈ 4,200" says the same thing without
    /// pretending. Values under 100 are already at or below two figures and pass through.
    static func roundedToTwoSignificantFigures(_ value: Int) -> Int {
        guard value >= 100 else { return value }
        var magnitude = 1
        var remaining = value / 100
        while remaining > 0 {
            magnitude *= 10
            remaining /= 10
        }
        // Integer half-up rounding at `magnitude`, e.g. 4,183 -> 4,200 and 996 -> 1,000.
        return ((value + magnitude / 2) / magnitude) * magnitude
    }
}
