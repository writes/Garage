import Foundation

enum ProfileFieldValue: Equatable, Sendable {
    case string(String)
    case boolean(Bool)

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }
}

typealias ProfileFields = [String: ProfileFieldValue]

struct UserProfile: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var email: String?
    var name: String?
    var address: String?
    var phone: String?
    var insuranceCompany: String?
    var policyNumber: String?
    var analyticsOptOut: Bool
    /// Selected accent-theme id (AccentScheme.rawValue). nil / empty = the default `.classic`.
    var themeID: String?
    var createdAt: Date?
    var updatedAt: Date?
}

extension UserProfile {
    init(id: String, profileFields: ProfileFields) {
        self.init(
            id: id,
            email: nil,
            name: profileFields["name"]?.stringValue,
            address: profileFields["address"]?.stringValue,
            phone: profileFields["phone"]?.stringValue,
            insuranceCompany: profileFields["insuranceCompany"]?.stringValue,
            policyNumber: profileFields["policyNumber"]?.stringValue,
            analyticsOptOut: profileFields["analyticsOptOut"]?.boolValue ?? true,
            themeID: profileFields["themeID"]?.stringValue,
            createdAt: nil,
            updatedAt: nil
        )
    }

    var profileFields: ProfileFields {
        [
            "name": .string(name ?? ""),
            "address": .string(address ?? ""),
            "phone": .string(phone ?? ""),
            "insuranceCompany": .string(insuranceCompany ?? ""),
            "policyNumber": .string(policyNumber ?? ""),
            "analyticsOptOut": .boolean(analyticsOptOut),
            "themeID": .string(themeID ?? "")
        ]
    }
}
