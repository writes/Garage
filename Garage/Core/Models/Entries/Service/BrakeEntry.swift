import Foundation

struct BrakeEntry: Codable, Sendable, Equatable {
    var action: BrakeServiceAction
    var position: BrakeServicePosition
    var padBrand: String?
    var padCompound: String?
    var rotorBrand: String?
    var padThicknessAtInstallMM: Double?
    var frontPadPct: Double?
    var rearPadPct: Double?
    var frontRotorPct: Double?
    var rearRotorPct: Double?
    var fluidFlushed: Bool
}

enum BrakeServiceAction: String, Codable, CaseIterable, Sendable {
    case padsReplaced = "pads_replaced"
    case rotorsReplaced = "rotors_replaced"
    case fluidFlush = "fluid_flush"
    case inspection
}

enum BrakeServicePosition: String, Codable, CaseIterable, Sendable {
    case front
    case rear
    case all
}
