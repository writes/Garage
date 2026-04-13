import Foundation

struct WearSnapshot: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var entryId: String?
    var wearItem: WearItemType
    var valuePct: Double?
    var valueRaw: String?
    var odometerReading: Int
    var recordedAt: Date
    var createdAt: Date?
}

enum WearItemType: String, Codable, CaseIterable, Sendable {
    case frontBrakePads = "front_brake_pads"
    case rearBrakePads = "rear_brake_pads"
    case frontRotors = "front_rotors"
    case rearRotors = "rear_rotors"
    case clutch
    case frontTires = "front_tires"
    case rearTires = "rear_tires"

    var label: String {
        switch self {
        case .frontBrakePads: return "Front Brake Pads"
        case .rearBrakePads: return "Rear Brake Pads"
        case .frontRotors: return "Front Rotors"
        case .rearRotors: return "Rear Rotors"
        case .clutch: return "Clutch"
        case .frontTires: return "Front Tires"
        case .rearTires: return "Rear Tires"
        }
    }
}

struct WearItem: Identifiable, Sendable, Equatable {
    let id = UUID()
    let type: WearItemType
    let percentage: Double
    let rawValue: String?
}
