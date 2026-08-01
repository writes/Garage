import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private let authService: AuthService
    // `internal` (not `private`): AppState+Actions.swift holds the user-action methods.
    let vehicleService: VehicleService
    let purchaseService: PurchaseService
    private let syncService: SyncService
    private let profileStore: any ProfileStore
    // `internal`: read by AppState+Actions.swift, same file-split precedent as vehicleService.
    let analytics: any AnalyticsTracking
    private let crashReporter: any CrashReporting
    private let notificationCoordinator: ReminderNotificationCoordinator

    var selectedTab: AppTab = .dashboard {
        didSet {
            guard oldValue != selectedTab else { return }
            analytics.track(.screenViewed(screen: selectedTab.analyticsScreen))
        }
    }
    var currentVehicle: Vehicle?
    var vehicles: [Vehicle] = []
    var userProfile: UserProfile?
    var syncStatus: SyncStatus = .idle
    var isBootstrapping = false
    /// Zero-vehicle-gate tri-state: "not yet loaded" must never read as "confirmed zero
    /// vehicles". True only after a real load; reset on sign-out/re-auth.
    private(set) var hasCompletedInitialVehicleLoad = false
    private var authenticationRevision = 0

    init(
        authService: AuthService = .shared,
        vehicleService: VehicleService = .shared,
        purchaseService: PurchaseService = .shared,
        syncService: SyncService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        crashReporter: (any CrashReporting)? = nil,
        profileStore: (any ProfileStore)? = nil,
        notificationCoordinator: ReminderNotificationCoordinator = .shared
    ) {
        self.authService = authService
        self.vehicleService = vehicleService
        self.purchaseService = purchaseService
        self.syncService = syncService
        self.analytics = analytics
        self.crashReporter = crashReporter ?? CrashReporter.shared
        self.profileStore = profileStore ?? ProfileStoreFactory.makeDefault()
        self.notificationCoordinator = notificationCoordinator
        analytics.setEnabled(false)
        // Crashlytics rides Analytics's consent lifecycle (#23): fail closed until profile load.
        self.crashReporter.setEnabled(false)
    }

    var isAuthenticated: Bool {
        _ = authenticationRevision
        return authService.isAuthenticated
    }

    /// The signed-in Firebase uid, for surfaces keyed per account (receipt-credits markers,
    /// the Q3-C paywall-dismissal flag). `authService` is `private` and Swift `private` is
    /// file-scoped, so sibling extension files read identity through this instead.
    var currentUserID: String? {
        _ = authenticationRevision
        return authService.uid
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
            hasCompletedInitialVehicleLoad = false
            return
        }

        if userProfile?.id != uid {
            userProfile = nil
            vehicles = []
            currentVehicle = nil
            hasCompletedInitialVehicleLoad = false
            // Defense-in-depth: an account switch must not carry the prior user's accent.
            AccentStore.shared.scheme = .classic
        }

        await loadProfile(uid: uid, expectedAuthenticationRevision: expectedAuthenticationRevision)
        guard authenticationMatches(expectedAuthenticationRevision, uid: uid) else { return }
        // Vehicles are NOT fetched here. `VehicleSyncHost`'s single live listener starts with the
        // authenticated shell and its first snapshot is the initial load — bootstrapping a
        // one-time fetch of the same collection alongside it just read the garage twice per cold
        // launch. `refreshVehicles()` remains for explicit user-triggered refreshes and as the
        // host's fallback when the listener fails before delivering anything.
        // Self-heal offline deletes (RULES-1): re-purge anything still tombstoned, off critical path.
        Task { await vehicleService.retryPendingPurges() }
    }

    /// Drives vehicles/currentVehicle from the live Firestore listener (#9). Stale-auth snapshots
    /// are impossible: the stream tears down on UID change before this can run.
    func applyVehicleSnapshot(_ envelope: VehicleSnapshotEnvelope) {
        var loadedVehicles = envelope.vehicles
        if !envelope.decodeFailureDocumentIDs.isEmpty {
            // Keeps a transiently undecodable doc's last-known copy; the sync badge surfaces it.
            let failed = Set(envelope.decodeFailureDocumentIDs)
            let retained = vehicles.filter { vehicle in
                failed.contains(vehicle.id) && !loadedVehicles.contains(where: { $0.id == vehicle.id })
            }
            loadedVehicles.append(contentsOf: retained)
            loadedVehicles.sort { $0.displayOrder < $1.displayOrder }
        }
        applyLoadedVehicles(loadedVehicles)
    }

    // No seed fallback: reseeding on empty resurrects ghosts after deleting the last vehicle.
    private func applyLoadedVehicles(_ loadedVehicles: [Vehicle]) {
        hasCompletedInitialVehicleLoad = true
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
            // Stale-fetch guard: an account switch mid-fetch must not apply the prior user's cars.
            guard authenticationMatches(expectedRevision, uid: uid) else { return }
            applyLoadedVehicles(loadedVehicles)
        } catch {
            AppLogger.shared.error("Vehicle refresh failed: \(error.localizedDescription)")
            crashReporter.record(error, context: "vehicle-refresh")
        }
    }

    func applyProfile(_ profile: UserProfile) {
        guard profile.id == authService.uid else {
            analytics.setEnabled(false)
            crashReporter.setEnabled(false)
            // Wrong identity: held pre-consent events must not survive to be flushed by whoever
            // consents next. See AnalyticsConsentGate.
            analytics.discardPendingEvents()
            return
        }
        userProfile = profile
        // Consent authority: a mid-session opt-out lands here; BOTH trackers must follow, or
        // Crashlytics (which persists its collection flag) leaks non-fatals.
        analytics.setEnabled(!profile.analyticsOptOut)
        crashReporter.setEnabled(!profile.analyticsOptOut)
        // After setEnabled: the reporter has no pending buffer, so an earlier call would be
        // silently dropped. A leftover trace means the last voice session died mid-flight.
        VoiceSessionTrace.shared.reportAbandonedTrace(to: crashReporter)
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
            VoiceSessionTrace.shared.reportAbandonedTrace(to: crashReporter)
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
            hasCompletedInitialVehicleLoad = false
            AccentStore.shared.scheme = .classic
            // Review findings: neither scheduled local reminder notifications nor QuickLook
            // preview temp-file residue were ever cleared here — the next person on this device
            // (a plain re-sign-in, OR account deletion, which funnels through this same
            // signOut()) could otherwise inherit the prior user's reminders/attachment bytes.
            notificationCoordinator.cancelAll()
            PDFPreviewTempFile.removeAll()
            authenticationRevision += 1
        } catch {
            AppLogger.shared.error("Sign out failed: \(error.localizedDescription)")
        }
    }
}
