import Foundation

struct Recall: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var campaignNumber: String?
    var title: String
    var description: String?
    var componentAffected: String?
    var dateAnnounced: Date?
    var status: RecallStatus
    var completedDate: Date?
    var completedShop: String?
    var completedOdometer: Int?
    var completedReceiptPath: String?
    var recallSource: RecallSource
    var notes: String?
    var createdAt: Date?
}

enum RecallStatus: String, Codable, Sendable {
    case outstanding
    case completed
    case notApplicable = "not_applicable"
}

enum RecallSource: String, Codable, Sendable {
    case manual
    case nhtsaApi = "nhtsa_api"
}
