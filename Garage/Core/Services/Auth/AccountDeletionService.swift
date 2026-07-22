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
        let callable = functions.httpsCallable("deleteAccount")
        // Match the Cloud Function's 300s budget so a large account doesn't hit the SDK's ~70s
        // default and surface a spurious timeout while the server is still deleting.
        callable.timeoutInterval = 300
        _ = try await callable.call([:])
    }
}
