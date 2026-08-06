import Foundation

/// Flags a real drop in fuel economy against the owner's own recent history.
///
/// Every fill-up already stores `calculatedMPG`, and the only thing the app did with it was draw a
/// line on a Pro chart nobody opens between services. A sustained MPG drop is one of the earliest
/// cheap-to-fix signals a car gives — under-inflated tires, a dragging brake, a thermostat stuck
/// open — and the owner cannot see it in a line that also contains one cold morning and one towing
/// weekend.
///
/// ## The averaging is the whole feature
///
/// The average is Σmiles ÷ Σgallons across the window, NEVER the mean of the per-tank MPG figures.
/// The mean-of-means is wrong car math: it weights a 4-gallon splash-and-dash exactly as heavily as
/// a 20-gallon fill, so one short top-up on a downhill run can hide a genuine drop (or invent one).
/// Each tank's distance is recovered exactly — `calculatedMPG` is defined as distance ÷ gallons, so
/// `calculatedMPG × gallons` returns the miles that tank covered — which makes the gallons-weighted
/// mean below identical to Σmiles ÷ Σgallons.
///
/// A fill-up missing either figure is dropped from the window entirely rather than weighted at one:
/// there is no honest weight for a tank whose size was not recorded, and inventing one is exactly
/// the error this note exists to prevent.
enum FuelEconomyAdvisor {
    /// What the car is doing now. Three tanks is roughly a fortnight of normal driving — long
    /// enough that one cold snap or one mountain trip cannot carry it alone.
    static let recentWindow = 3

    /// What the car normally does. Deliberately INCLUDES the recent three rather than sitting
    /// beside them: a drop must be large enough to show through its own dilution, which makes the
    /// flag conservative in the direction that matters. A window excluding them would fire more
    /// often and be wrong more often.
    static let baselineWindow = 10

    /// Below 15% the difference is seasonal (winter fuel, cold starts, A/C) rather than mechanical,
    /// and a flag that fires every autumn is a flag owners learn to ignore.
    static let dropThresholdPct = 15.0

    struct Verdict: Equatable, Sendable {
        /// Σmiles ÷ Σgallons across the most recent `recentWindow` qualifying fill-ups.
        let currentAvgMPG: Double
        /// The same figure across the most recent `baselineWindow`.
        let baselineAvgMPG: Double
        /// How far `currentAvgMPG` sits below `baselineAvgMPG`, in percent.
        let dropPct: Double
    }

    /// One qualifying fill-up: an MPG figure and the tank size that earns it its weight.
    private struct Tank {
        let id: String
        let date: Date
        let mpg: Double
        let gallons: Double

        /// Miles this tank covered. `calculatedMPG` is distance ÷ gallons, so this inverts exactly
        /// — no re-derivation from odometers, which are not contiguous in a mixed-type feed.
        var miles: Double { mpg * gallons }
    }

    /// Nil unless there is a full baseline window AND the recent window is more than
    /// `dropThresholdPct` below it. Nil is the answer in every ambiguous case: telling an owner
    /// their engine is sick on the strength of four fill-ups is how an app loses the one kind of
    /// trust it needs.
    static func degradation(in entries: [FirestoreEntry]) -> Verdict? {
        let tanks = entries
            .compactMap(Self.tank(from:))
            // Newest first. The id tiebreak makes the window a total order: two fill-ups on the
            // same date are ordinary (a top-up on the way home), and Swift's sort is not stable.
            .sorted { ($0.date, $0.id) > ($1.date, $1.id) }

        guard tanks.count >= Self.baselineWindow,
              let current = Self.averageMPG(tanks.prefix(Self.recentWindow)),
              let baseline = Self.averageMPG(tanks.prefix(Self.baselineWindow)),
              baseline > 0 else { return nil }

        let dropPct = (baseline - current) / baseline * 100
        guard dropPct > Self.dropThresholdPct else { return nil }
        return Verdict(currentAvgMPG: current, baselineAvgMPG: baseline, dropPct: dropPct)
    }

    private static func tank(from entry: FirestoreEntry) -> Tank? {
        guard entry.entryType == .fuel,
              let mpg = entry.details["calculatedMPG"]?.value.doubleValue, mpg > 0,
              let gallons = entry.details["gallons"]?.value.doubleValue, gallons > 0 else { return nil }
        return Tank(id: entry.id, date: entry.entryDate, mpg: mpg, gallons: gallons)
    }

    /// Σmiles ÷ Σgallons — see the type note. Nil on an empty slice rather than zero MPG.
    private static func averageMPG(_ tanks: ArraySlice<Tank>) -> Double? {
        let gallons = tanks.reduce(0.0) { $0 + $1.gallons }
        guard gallons > 0 else { return nil }
        return tanks.reduce(0.0) { $0 + $1.miles } / gallons
    }
}
