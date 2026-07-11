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
        profileStore: (any ProfileStore)? = nil
    ) {
        self.authService = authService
        self.vehicleService = vehicleService
        self.purchaseService = purchaseService
        self.syncService = syncService
        self.analytics = analytics
        self.profileStore = profileStore ?? ProfileStoreFactory.makeDefault()
        analytics.setEnabled(false)
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
        }

        await loadProfile(uid: uid, expectedAuthenticationRevision: expectedAuthenticationRevision)
        guard authenticationMatches(expectedAuthenticationRevision, uid: uid) else { return }
        await loadVehicles(uid: uid, expectedAuthenticationRevision: expectedAuthenticationRevision)
    }

    private func loadVehicles(uid: String, expectedAuthenticationRevision: Int) async {
        do {
            let loadedVehicles = try await vehicleService.fetchVehicles()
            guard authenticationMatches(expectedAuthenticationRevision, uid: uid) else { return }
            vehicles = loadedVehicles
            if let currentVehicle,
               let matchingVehicle = loadedVehicles.first(where: { $0.id == currentVehicle.id }) {
                self.currentVehicle = matchingVehicle
            } else {
                currentVehicle = loadedVehicles.min(by: { $0.displayOrder < $1.displayOrder })
            }
            #if DEBUG
            if vehicles.isEmpty {
                vehicles = SeedData.vehicles
                currentVehicle = vehicles.first
            }
            #endif
        } catch {
            AppLogger.shared.error("App bootstrap failed: \(error.localizedDescription)")
        }
    }

    func refreshVehicles() async {
        do {
            vehicles = try await vehicleService.fetchVehicles()
            if let currentVehicle, vehicles.contains(where: { $0.id == currentVehicle.id }) {
                self.currentVehicle = vehicles.first(where: { $0.id == currentVehicle.id })
            } else {
                self.currentVehicle = vehicles.first
            }
        } catch {
            AppLogger.shared.error("Vehicle refresh failed: \(error.localizedDescription)")
        }
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
            return
        }
        userProfile = profile
    }

    private func loadProfile(uid: String, expectedAuthenticationRevision: Int) async {
        do {
            let profile = try await ProfileViewModel.loadProfile(uid: uid, store: profileStore)
            guard authenticationMatches(expectedAuthenticationRevision, uid: uid) else {
                analytics.setEnabled(false)
                return
            }
            userProfile = profile
            analytics.setEnabled(!profile.analyticsOptOut)
        } catch {
            userProfile = nil
            analytics.setEnabled(false)
            AppLogger.shared.error("Profile bootstrap failed: \(error.localizedDescription)")
        }
    }

    private func authenticationMatches(_ expectedRevision: Int, uid: String? = nil) -> Bool {
        guard authService.authenticationRevision == expectedRevision else { return false }
        return uid.map { authService.uid == $0 } ?? true
    }

    func signOut() {
        analytics.setEnabled(false)
        do {
            try authService.signOut()
            userProfile = nil
            vehicles = []
            currentVehicle = nil
            authenticationRevision += 1
        } catch {
            AppLogger.shared.error("Sign out failed: \(error.localizedDescription)")
        }
    }
}

enum SeedData {
    static let vehicles: [Vehicle] = [
        Vehicle(
            id: "seed-viper",
            userId: "debug-user",
            nickname: "Viper ACR",
            make: "Dodge",
            model: "Viper ACR",
            year: 2008,
            currentOdometer: 18_240,
            fuelType: .premium93,
            color: "Red",
            displayOrder: 0
        ),
        Vehicle(
            id: "seed-sq5",
            userId: "debug-user",
            nickname: "Daily SQ5",
            make: "Audi",
            model: "SQ5",
            year: 2015,
            currentOdometer: 82_440,
            fuelType: .premium91,
            color: "Gray",
            displayOrder: 1
        )
    ]
}
