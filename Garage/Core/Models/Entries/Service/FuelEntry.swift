import Foundation

struct FuelEntry: Codable, Sendable, Equatable {
    var gallons: Double
    var pricePerGallon: Double
    var totalCost: Double
    var stationName: String?
    var fuelGrade: FuelType
    var calculatedMPG: Double?
}
