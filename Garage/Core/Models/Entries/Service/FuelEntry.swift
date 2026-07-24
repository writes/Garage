import Foundation

struct FuelEntry: Codable, Sendable, Equatable {
    var gallons: Double
    var pricePerGallon: Double
    var totalCost: Double
    var stationName: String?
    var fuelGrade: FuelType
    var calculatedMPG: Double?
}

extension FuelEntry {
    /// Full-to-full MPG between two consecutive fill-ups. This assumes every fill-up tops off the
    /// tank — there is no reliable signal in a logged entry to detect a partial fill, so one will
    /// silently skew the figure. Returns nil for a non-positive distance or a non-positive gallons
    /// value (out-of-order entry, a corrected odometer, or missing gallons).
    static func calculatedMPG(currentOdometer: Int, previousOdometer: Int, gallons: Double) -> Double? {
        let distance = currentOdometer - previousOdometer
        guard distance > 0, gallons > 0 else { return nil }
        return Double(distance) / gallons
    }
}
