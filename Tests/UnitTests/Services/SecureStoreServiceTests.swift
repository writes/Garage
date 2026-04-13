import Testing
@testable import Garage

@MainActor
struct SecureStoreServiceTests {
    @Test func deleteValue_allowsMissingKey() {
        SecureStoreService.shared.deleteValue(for: "missing-key")
        #expect(true)
    }
}
