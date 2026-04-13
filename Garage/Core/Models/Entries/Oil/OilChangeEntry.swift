import Foundation

struct OilChangeEntry: Codable, Sendable, Equatable {
    var oilBrand: String
    var oilGrade: String
    var quantityQuarts: Double
    var filterBrand: String?
}
