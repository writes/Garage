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
    /// When this account allowed voice/receipt content to be sent to the Claude API (5.1.2(i)).
    /// nil = never granted, or revoked. Encoding lives in UserProfile+AIConsent.swift.
    var aiConsentGrantedAt: Date?
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
            aiConsentGrantedAt: Self.decodeAIConsent(profileFields[Self.aiConsentFieldKey]),
            createdAt: nil,
            updatedAt: nil
        )
    }

    /// The full-document encoding — decode symmetry with `init(id:profileFields:)`. NOT what the
    /// profile form writes: `save()` sends `formOwnedFields`, because writing a field HERE writes
    /// it BY VALUE, and a cached copy of a field another surface owns (themeID from the picker,
    /// aiConsentGrantedAt from Settings/AppState) can be stale — a full save carrying a stale
    /// grant silently un-revoked a Settings-side consent revoke (2026-08-03 cross-check).
    var profileFields: ProfileFields {
        [
            "name": .string(name ?? ""),
            "address": .string(address ?? ""),
            "phone": .string(phone ?? ""),
            "insuranceCompany": .string(insuranceCompany ?? ""),
            "policyNumber": .string(policyNumber ?? ""),
            "analyticsOptOut": .boolean(analyticsOptOut),
            "themeID": .string(themeID ?? ""),
            Self.aiConsentFieldKey: .string(Self.encodeAIConsent(aiConsentGrantedAt))
        ]
    }

    /// What the profile FORM saves: only the fields its screen edits. The store write is
    /// `setData(merge: true)`, so a key absent here is left untouched on the document — which is
    /// what protects `themeID` (owned by the theme picker) and `aiConsentGrantedAt` (owned by
    /// AppState/Settings) from being overwritten with whatever stale value this screen cached.
    var formOwnedFields: ProfileFields {
        [
            "name": .string(name ?? ""),
            "address": .string(address ?? ""),
            "phone": .string(phone ?? ""),
            "insuranceCompany": .string(insuranceCompany ?? ""),
            "policyNumber": .string(policyNumber ?? ""),
            "analyticsOptOut": .boolean(analyticsOptOut)
        ]
    }
}
