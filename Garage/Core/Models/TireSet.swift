import Foundation

struct TireSet: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var nickname: String
    var brand: String
    var model: String
    var sizeFront: String?
    var sizeRear: String?
    var installedOdometer: Int
    var heatCycles: Int
    var notes: String?
}
