import Foundation

struct OilConsumptionEntry: Codable, Sendable, Equatable {
    var amountAddedQuarts: Double
    var runningTotalSinceLastChange: Double?
    var oilBrand: String?
    var oilGrade: String?
}
