import FirebaseFunctions
import Foundation
import Observation

@MainActor
protocol AccountDeleting {
    /// Permanently deletes the signed-in user's Firestore data, Storage files, and auth record via
    /// the deleteAccount Cloud Function. The caller signs out locally afterward.
    func deleteAccount() async throws
}

@MainActor
@Observable
final class AccountDeletionService: AccountDeleting {
    static let shared = AccountDeletionService()

    private let functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func deleteAccount() async throws {
        _ = try await functions.httpsCallable("deleteAccount").call([:])
    }
}
