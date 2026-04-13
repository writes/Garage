import Foundation

struct Warranty: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var warrantyType: WarrantyType
    var basicTermMonths: Int?
    var basicTermMiles: Int?
    var powertrainTermMonths: Int?
    var powertrainTermMiles: Int?
    var corrosionTermMonths: Int?
    var roadsideTermMonths: Int?
    var expirationDate: Date?
    var providerName: String?
    var planName: String?
    var coverageStart: Date?
    var coverageEnd: Date?
    var mileageLimit: Int?
    var deductible: Double?
    var contractNumber: String?
    var providerPhone: String?
    var coverageDescription: String?
    var exclusions: String?
    var documentPath: String?
    var startDate: Date
    var notes: String?
    var createdAt: Date?
}

enum WarrantyType: String, Codable, Sendable {
    case factory
    case extended
}
