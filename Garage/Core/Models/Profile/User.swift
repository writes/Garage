import Foundation

struct UserProfile: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var email: String?
    var name: String?
    var address: String?
    var phone: String?
    var insuranceCompany: String?
    var policyNumber: String?
    var analyticsOptOut: Bool
    var createdAt: Date?
    var updatedAt: Date?
}
