import Foundation

struct TireEntry: Codable, Sendable, Equatable {
    var actionType: TireActionType
    var tireBrand: String
    var tireModel: String
    var tireSetId: String?
    var tireSizeFront: String?
    var tireSizeRear: String?
    var position: TirePosition
    var treadDepthFL: String?
    var treadDepthFR: String?
    var treadDepthRL: String?
    var treadDepthRR: String?
    var heatCycles: Int?
    var compound: String?
    var treadwearRating: String?
}

enum TireActionType: String, Codable, CaseIterable, Sendable {
    case newInstall = "new_install"
    case rotation
    case treadDepthReading = "tread_depth_reading"
    case removed
}

enum TirePosition: String, Codable, CaseIterable, Sendable {
    case frontLeft = "fl"
    case frontRight = "fr"
    case rearLeft = "rl"
    case rearRight = "rr"
    case front
    case rear
    case allFour = "all_four"
}
