import Foundation

struct SparePart: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var name: String
    var category: PartCategory
    var brand: String?
    var partNumber: String?
    var quantity: Int
    var unitCost: Double?
    var wherePurchased: String?
    var purchaseDate: Date?
    var storageLocation: String?
    var condition: PartCondition
    var photoStoragePath: String?
    var receiptStoragePath: String?
    var isConsumed: Bool
    var consumedAtEntryId: String?
    var notes: String?
}

enum PartCategory: String, Codable, CaseIterable, Sendable {
    case engine
    case suspension
    case brakes
    case body
    case interior
    case wheels
    case other
}

enum PartCondition: String, Codable, CaseIterable, Sendable {
    case new
    case used
    case refurbished
}
