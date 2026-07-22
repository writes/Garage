import Foundation

struct Vehicle: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var userId: String
    var nickname: String
    var make: String
    var model: String
    var year: Int
    var licensePlate: String?
    var purchaseDate: Date?
    var purchasePrice: Double?
    var currentOdometer: Int
    var odometerAtPurchase: Int?
    var engineOilType: String?
    var tireSizeFront: String?
    var tireSizeRear: String?
    var fuelType: FuelType?
    var vin: String?
    var color: String?
    var weightClass: String?
    var notes: String?
    var externalHistory: [String: AnyCodable]?
    var displayOrder: Int = 0
    var createdAt: Date?
    var updatedAt: Date?
    /// Soft-delete tombstone (RULES-1): set by the client, purged (with the counter decrement)
    /// by the deleteVehicle Cloud Function. Tombstoned vehicles are hidden everywhere.
    var deletedAt: Date?

    static let empty = Vehicle(
        id: UUID().uuidString,
        userId: "",
        nickname: "",
        make: "",
        model: "",
        year: Calendar.current.component(.year, from: Date.now),
        currentOdometer: 0
    )

    var displayName: String {
        nickname.isNotEmpty ? nickname : "\(year) \(make) \(model)"
    }
}

enum FuelType: String, Codable, CaseIterable, Sendable {
    case regular87 = "regular_87"
    case premium91 = "premium_91"
    case premium93 = "premium_93"
    case e85
    case diesel
}
