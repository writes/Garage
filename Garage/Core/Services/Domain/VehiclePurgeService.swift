import FirebaseFunctions
import Foundation

@MainActor
protocol VehiclePurging {
    /// Deletes the vehicle document, its subcollections, and decrements the server-side
    /// vehicle counter via the deleteVehicle Cloud Function (RULES-1). Idempotent: retrying
    /// after a partial failure converges to fully-deleted.
    func purgeVehicle(id: String) async throws
}

@MainActor
final class VehiclePurgeService: VehiclePurging {
    static let shared = VehiclePurgeService()

    private let functions = Functions.functions(region: Secrets.anthroProxyRegion)

    private init() {}

    func purgeVehicle(id: String) async throws {
        let callable = functions.httpsCallable("deleteVehicle")
        // Match the Cloud Function's 120s budget (recursive subcollection delete can be slow
        // for a heavily-logged vehicle) instead of the SDK's ~70s default.
        callable.timeoutInterval = 120
        _ = try await callable.call(["vehicleId": id])
    }
}
