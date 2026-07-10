import Foundation
import Testing
@testable import Garage

@MainActor
struct SecureStoreServiceTests {
    @Test func saveReadDelete_roundTripsThroughKeychain() throws {
        let identifier = UUID().uuidString
        let service = SecureStoreService(service: "GarageTests.\(identifier)")
        let account = "account-\(identifier)"
        let value = Data("sensitive test value".utf8)
        defer { service.deleteValue(for: account) }

        let missingBeforeSave = try service.readValue(for: account)
        #expect(missingBeforeSave == nil)
        try service.save(value: value, for: account)
        let readValue = try service.readValue(for: account)
        #expect(readValue == value)

        service.deleteValue(for: account)
        let missingAfterDelete = try service.readValue(for: account)
        #expect(missingAfterDelete == nil)
    }

    @Test func deleteValue_allowsMissingUniqueKey() throws {
        let identifier = UUID().uuidString
        let service = SecureStoreService(service: "GarageTests.\(identifier)")
        let account = "missing-\(identifier)"
        defer { service.deleteValue(for: account) }

        service.deleteValue(for: account)

        let missingValue = try service.readValue(for: account)
        #expect(missingValue == nil)
    }
}
