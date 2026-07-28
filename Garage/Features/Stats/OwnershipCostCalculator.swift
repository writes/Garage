import Foundation

/// Derives ownership economics from entries the app already stores.
///
/// Every ingredient — cost, odometer, date — has been recorded since v1, and nothing was computed
/// from it: Stats showed what you typed back to you. Cost per mile is the number an owner actually
/// wants, and it is also the number a resale buyer respects, so it does double duty for the
/// dossier the product is built around.
///
/// Pure and `nonisolated` so every rule below is testable without Firestore or a view.
enum OwnershipCostCalculator {
    struct Summary: Equatable, Sendable {
        let totalCost: Double
        let milesCovered: Int
        let costPerMile: Double?
        let costPerMonth: Double?
        let monthsCovered: Double
    }

    /// A single entry cannot establish a distance or a duration, so the summary is nil rather than
    /// zero. Showing "$0.00/mi" for a one-entry history would be a confident-looking lie.
    static func summary(for entries: [FirestoreEntry], now: Date) -> Summary? {
        let costed = entries.filter { ($0.cost ?? 0) > 0 }
        guard !costed.isEmpty else { return nil }

        let total = costed.reduce(0.0) { $0 + ($1.cost ?? 0) }

        // Distance uses EVERY entry's odometer, not just costed ones: a free warranty repair still
        // proves the car covered those miles, and excluding it would overstate cost per mile.
        let odometers = entries.map(\.odometerReading).filter { $0 > 0 }
        let miles = (odometers.max() ?? 0) - (odometers.min() ?? 0)

        let dates = entries.map(\.entryDate)
        let span = (dates.max() ?? now).timeIntervalSince(dates.min() ?? now)
        let months = span / (30.44 * 24 * 60 * 60)

        return Summary(
            totalCost: total,
            milesCovered: miles,
            // Guarded, not clamped: two entries logged at the same odometer are a real case
            // (same-day service plus fuel), and dividing by that zero would produce infinity.
            costPerMile: miles > 0 ? total / Double(miles) : nil,
            // Below roughly a month there is no meaningful monthly rate — annualising three days
            // of ownership produces a number that is arithmetically true and practically absurd.
            costPerMonth: months >= 1 ? total / months : nil,
            monthsCovered: months
        )
    }
}
