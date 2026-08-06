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

/// Minimal `details` probe for what a tire entry actually DID.
///
/// Decoding the full `TireEntry` would be wrong, not merely wasteful: it has four non-optional
/// fields, so any legacy or partial map fails to decode and a perfectly good tire record is
/// silently dropped. Shared by every reader that only needs the action discriminator, so two
/// readers cannot drift into disagreeing about the same entry.
struct TireActionProbe: Decodable, Sendable {
    var actionType: TireActionType?
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
