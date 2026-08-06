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

    /// The two axles are tracked separately because an axle is only as good as its most worn tire —
    /// but they share one set of rubber-age evidence, since a tire entry carries no reliable
    /// per-axle scoping for an installation.
    var isTire: Bool { self == .frontTires || self == .rearTires }
}

struct WearItem: Identifiable, Sendable, Equatable {
    let id = UUID()
    let type: WearItemType
    let percentage: Double
    let rawValue: String?
    /// Miles until this item reaches 0% at the rate its own history implies, or nil whenever the
    /// history cannot support the claim — see `WearProjection`. Nil is the ordinary case, and no
    /// caller may substitute a zero or a placeholder for it.
    let milesToReplacement: Int?
}
