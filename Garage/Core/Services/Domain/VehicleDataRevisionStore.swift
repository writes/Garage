import Observation

/// Mutation-driven invalidation for per-vehicle read caches.
///
/// Domain services bump the counter for a vehicle right after a live write succeeds; view models
/// compare `(vehicleId, revision)` against the pair they last loaded and skip a refetch when it is
/// unchanged. This turns "reload on every tab return" into "reload only when something actually
/// changed," without a snapshot listener on every collection. Mirrors `DemoSessionStore.revision`,
/// the established invalidation pattern for the local-demo overlay.
@MainActor
@Observable
final class VehicleDataRevisionStore {
    static let shared = VehicleDataRevisionStore()

    private(set) var revisions: [String: Int] = [:]

    /// Hermetic-test friendly: a plain init lets tests use a non-shared instance instead of
    /// mutating the process-wide singleton.
    init() {}

    func bump(vehicleId: String) {
        revisions[vehicleId, default: 0] += 1
    }

    func revision(for vehicleId: String) -> Int {
        revisions[vehicleId] ?? 0
    }

    /// Whether a gated view model should ever skip a refetch on a matching (vehicleId, revision).
    /// Live-only: demo writes bump `DemoSessionStore.revision` (a separate counter) instead of this
    /// store, and UI-test journeys mutate then re-check views in-process, so gating on this store's
    /// revision there would skip real UI refreshes. Demo/UI-test fetches are in-memory and free
    /// anyway, so there's no cost to always reloading in those runtimes.
    static var skipGateIsEnabled: Bool {
        !AppRuntime.isLocalDemoMode && !AppRuntime.isUITestMode
    }
}
