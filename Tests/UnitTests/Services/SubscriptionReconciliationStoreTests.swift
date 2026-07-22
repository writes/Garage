import Foundation
import Testing
@testable import Garage

@MainActor
struct SubscriptionReconciliationStoreTests {
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "test.recon.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test func identityBoundReconciliationBlocksAndClearsOnMatchingUID() {
        let (defaults, _) = freshDefaults()
        let store = SubscriptionReconciliationStore(defaults: defaults)
        store.observePurchase(.reconciliationRequired, uid: "user-A")
        #expect(store.kind == .purchase) // blocks the purchase path

        store.observeRestore(.activeEntitlement, uid: "user-B") // wrong identity
        #expect(store.kind == .purchase) // still blocked

        store.observeRestore(.activeEntitlement, uid: "user-A") // reconciled
        #expect(store.kind == nil)
    }

    @Test func nilUIDReconciliationNeverBlocksThePurchasePath() {
        let (defaults, _) = freshDefaults()
        let store = SubscriptionReconciliationStore(defaults: defaults)
        // A reconciliation observed while identity is unresolved has no uid -> can never be cleared,
        // so it must NOT block (a permanent brick). BLOCKER #3 regression guard.
        store.observePurchase(.reconciliationRequired, uid: nil)
        #expect(store.kind == nil)
        store.observeRestore(.reconciliationRequired, uid: nil)
        #expect(store.kind == nil)
    }

    @Test func corruptStoredBlobIsClearedNotTurnedIntoABrick() {
        let suite = "test.recon.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let key = SubscriptionReconciliationStore.storageKey
        defaults.set(Data("not-decodable-json".utf8), forKey: key)

        let store = SubscriptionReconciliationStore(defaults: defaults, key: key)
        #expect(store.kind == nil) // corrupt -> no reconciliation (not a nil-uid brick)
        #expect(defaults.data(forKey: key) == nil) // corrupt blob reaped
    }
}
