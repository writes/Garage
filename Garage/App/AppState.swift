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
        syncService: SyncService = .shared
    ) {
        self.authService = authService
        self.vehicleService = vehicleService
        self.purchaseService = purchaseService
        self.syncService = syncService
    }

    var isAuthenticated: Bool {
        _ = authenticationRevision
        return authService.isAuthenticated
    }

    var isPro: Bool {
        purchaseService.isPro
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        if AppRuntime.isLocalDemoMode {
            syncStatus = .upToDate
        } else {
            await purchaseService.checkSubscriptionStatus()
            syncStatus = syncService.currentStatus
        }

        guard authService.isAuthenticated else { return }

        do {
            vehicles = try await vehicleService.fetchVehicles()
            if currentVehicle == nil {
                currentVehicle = vehicles.min(by: { $0.displayOrder < $1.displayOrder })
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

    func signOut() {
        do {
            try authService.signOut()
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
