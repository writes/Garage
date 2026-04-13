import Foundation

struct DetailingRecord: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var serviceDate: Date
    var serviceType: DetailingType
    var title: String
    var providerName: String?
    var productName: String?
    var correctionType: String?
    var coverageArea: String?
    var layers: Int?
    var warrantyExpiration: Date?
    var maintenanceScheduleNotes: String?
    var cost: Double?
    var notes: String?
    var attachmentPaths: [String]
}

enum DetailingType: String, Codable, CaseIterable, Sendable {
    case wash
    case paintCorrection = "paint_correction"
    case ceramic
    case ppf
    case interior
    case cosmeticImprovement = "cosmetic_improvement"
}
