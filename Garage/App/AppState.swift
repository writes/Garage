import Foundation
import Observation

enum SyncStatus: String, Sendable {
    case idle
    case upToDate
    case syncing
    case offline
    case attentionNeeded

    var label: String {
        switch self {
        case .idle: return "Up to date"
        case .upToDate: return "Up to date"
        case .syncing: return "Syncing"
        case .offline: return "Offline"
        case .attentionNeeded: return "Needs attention"
        }
    }
}

@MainActor
@Observable
final class AppState {
    private let authService: AuthService
    private let vehicleService: VehicleService
    let purchaseService: PurchaseService
    private let syncService: SyncService
    private let profileStore: any ProfileStore
    private let analytics: any AnalyticsTracking
    private let crashReporter: any CrashReporting

    var selectedTab: AppTab = .dashboard
    var currentVehicle: Vehicle?
    var vehicles: [Vehicle] = []
    var userProfile: UserProfile?
    var syncStatus: SyncStatus = .idle
    var isBootstrapping = false
    private var authenticationRevision = 0

    init(
        authService: AuthService = .shared,
        vehicleService: VehicleService = .shared,
        purchaseService: PurchaseService = .shared,
        syncService: SyncService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        crashReporter: (any CrashReporting)? = nil,
        profileStore: (any ProfileStore)? = nil
    ) {
        self.authService = authService
        self.vehicleService = vehicleService
        self.purchaseService = purchaseService
        self.syncService = syncService
        self.analytics = analytics
        self.crashReporter = crashReporter ?? CrashReporter.shared
        self.profileStore = profileStore ?? ProfileStoreFactory.makeDefault()
        analytics.setEnabled(false)
        // Crashlytics rides the same consent lifecycle as Analytics (#23): fail closed until a
        // profile load confirms the stored opt-in.
        self.crashReporter.setEnabled(false)
    }

    var isAuthenticated: Bool {
        _ = authenticationRevision
        return authService.isAuthenticated
    }

    var authenticationStateID: Int {
        _ = authenticationRevision
        return authService.authenticationRevision
    }

    var isPro: Bool {
        purchaseService.isPro
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        var expectedAuthenticationRevision: Int
        repeat {
            expectedAuthenticationRevision = authService.authenticationRevision
            await bootstrap(expectedAuthenticationRevision: expectedAuthenticationRevision)
        } while authService.authenticationRevision != expectedAuthenticationRevision
    }

    private func bootstrap(expectedAuthenticationRevision: Int) async {
        analytics.setEnabled(false)
        crashReporter.setEnabled(false)

        if AppRuntime.isLocalDemoMode {
            syncStatus = .upToDate
        } else {
            await purchaseService.checkSubscriptionStatus()
            syncStatus = syncService.currentStatus
        }

        guard authenticationMatches(expectedAuthenticationRevision),
              authService.isAuthenticated,
              let uid = authService.uid else {
            userProfile = nil
            vehicles = []
            currentVehicle = nil
            return
        }

        if userProfile?.id != uid {
            userProfile = nil
            vehicles = []
            currentVehicle = nil
            // Defense-in-depth: an account switch must not carry the prior user's accent even if
            // the new profile load fails before applying its own themeID.
            AccentStore.shared.scheme = .classic
        }

        await loadProfile(uid: uid, expectedAuthenticationRevision: expectedAuthenticationRevision)
        guard authenticationMatches(expectedAuthenticationRevision, uid: uid) else { return }
        await loadVehicles(uid: uid, expectedAuthenticationRevision: expectedAuthenticationRevision)
        // Self-heal offline deletes (RULES-1): re-purge anything still tombstoned, off the
        // critical path.
        Task { await vehicleService.retryPendingPurges() }
    }

    private func loadVehicles(uid: String, expectedAuthenticationRevision: Int) async {
        do {
            let loadedVehicles = try await vehicleService.fetchVehicles()
            guard authenticationMatches(expectedAuthenticationRevision, uid: uid) else { return }
            applyLoadedVehicles(loadedVehicles)
        } catch {
            AppLogger.shared.error("App bootstrap failed: \(error.localizedDescription)")
            crashReporter.record(error, context: "vehicle-bootstrap")
        }
    }

    /// Drives vehicles/currentVehicle from the live Firestore listener (#9) so edits from other
    /// devices or screens land without a manual refresh. Stale-auth snapshots are impossible
    /// here: the stream is torn down on UID change (VehicleSwitcher's .task(id:) scope) before
    /// this can run.
    func applyVehicleSnapshot(_ envelope: VehicleSnapshotEnvelope) {
        var loadedVehicles = envelope.vehicles
        if !envelope.decodeFailureDocumentIDs.isEmpty {
            // Keep the last-known copy of a transiently undecodable doc so it neither vanishes
            // nor steals the selection; the sync badge surfaces the decode diagnostic.
            let failed = Set(envelope.decodeFailureDocumentIDs)
            let retained = vehicles.filter { vehicle in
                failed.contains(vehicle.id) && !loadedVehicles.contains(where: { $0.id == vehicle.id })
            }
            loadedVehicles.append(contentsOf: retained)
            loadedVehicles.sort { $0.displayOrder < $1.displayOrder }
        }
        applyLoadedVehicles(loadedVehicles)
    }

    // Deliberately NO seed fallback here: live-listener envelopes feed this path, and reseeding
    // on empty resurrected ghosts after deleting the last vehicle. Seeds live in uiTest/demo modes.
    private func applyLoadedVehicles(_ loadedVehicles: [Vehicle]) {
        vehicles = loadedVehicles
        if let currentVehicle,
           let matchingVehicle = loadedVehicles.first(where: { $0.id == currentVehicle.id }) {
            self.currentVehicle = matchingVehicle
        } else {
            currentVehicle = loadedVehicles.min(by: { $0.displayOrder < $1.displayOrder })
        }
    }

    func refreshVehicles() async {
        guard let uid = authService.uid else { return }
        let expectedRevision = authService.authenticationRevision
        do {
            let loadedVehicles = try await vehicleService.fetchVehicles()
            // Same stale-fetch guard as loadVehicles (no resurrecting a prior account's list).
            guard authenticationMatches(expectedRevision, uid: uid) else { return }
            applyLoadedVehicles(loadedVehicles)
        } catch {
            AppLogger.shared.error("Vehicle refresh failed: \(error.localizedDescription)")
            crashReporter.record(error, context: "vehicle-refresh")
        }
    }

    /// Tombstones the vehicle (it disappears immediately) and purges it server-side (RULES-1).
    func deleteVehicle(_ vehicle: Vehicle) async throws {
        try await vehicleService.deleteVehicle(vehicle)
        await refreshVehicles()
    }

    func selectVehicle(_ vehicle: Vehicle) {
        currentVehicle = vehicle
    }

    func paywallDidAppear(source: PaywallSource) {
        analytics.track(.paywallViewed(source: source))
    }

    func applyProfile(_ profile: UserProfile) {
        guard profile.id == authService.uid else {
            analytics.setEnabled(false)
            crashReporter.setEnabled(false)
            return
        }
        userProfile = profile
        // Consent authority: a mid-session opt-out lands here, and BOTH trackers must follow —
        // Crashlytics persisted its collection flag when enabled, so skipping this leaks non-fatals.
        analytics.setEnabled(!profile.analyticsOptOut)
        crashReporter.setEnabled(!profile.analyticsOptOut)
        AccentStore.shared.apply(themeID: profile.themeID)
    }

    private func loadProfile(uid: String, expectedAuthenticationRevision: Int) async {
        do {
            let profile = try await ProfileViewModel.loadProfile(uid: uid, store: profileStore)
            guard authenticationMatches(expectedAuthenticationRevision, uid: uid) else {
                analytics.setEnabled(false)
                crashReporter.setEnabled(false)
                return
            }
            userProfile = profile
            analytics.setEnabled(!profile.analyticsOptOut)
            crashReporter.setEnabled(!profile.analyticsOptOut)
            AccentStore.shared.apply(themeID: profile.themeID)
        } catch {
            userProfile = nil
            analytics.setEnabled(false)
            crashReporter.setEnabled(false)
            AccentStore.shared.scheme = .classic
            AppLogger.shared.error("Profile bootstrap failed: \(error.localizedDescription)")
        }
    }

    private func authenticationMatches(_ expectedRevision: Int, uid: String? = nil) -> Bool {
        guard authService.authenticationRevision == expectedRevision else { return false }
        return uid.map { authService.uid == $0 } ?? true
    }

    func signOut() {
        analytics.setEnabled(false)
        crashReporter.setEnabled(false)
        do {
            try authService.signOut()
            userProfile = nil
            vehicles = []
            currentVehicle = nil
            AccentStore.shared.scheme = .classic
            authenticationRevision += 1
        } catch {
            AppLogger.shared.error("Sign out failed: \(error.localizedDescription)")
        }
    }
}
