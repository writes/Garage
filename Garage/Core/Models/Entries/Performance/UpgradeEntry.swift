import Foundation

struct UpgradeEntry: Codable, Sendable, Equatable {
    var title: String
    var brand: String?
    var partNumber: String?
    var category: UpgradeCategory
}

enum UpgradeCategory: String, Codable, CaseIterable, Sendable {
    case suspension
    case engine
    case aero
    case interior
    case wheels
    case other
}
