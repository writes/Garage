import Foundation

struct RepairEntry: Codable, Sendable, Equatable {
    var title: String
    var symptomDescription: String?
    var resolutionDescription: String?
    var status: ServiceStatus
    var replacedParts: [String]
}
