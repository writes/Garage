import Foundation

// User-action methods, split from AppState.swift purely for the file-length cap (same
// precedent as EntryFormViewModel's +DetailsEncoding split).
extension AppState {
    /// Tombstones the vehicle (disappears immediately), purges server-side (RULES-1).
    func deleteVehicle(_ vehicle: Vehicle) async throws {
        try await vehicleService.deleteVehicle(vehicle)
        analytics.track(.vehicleDeleted)
        await refreshVehicles()
    }

    /// No-ops on re-selecting the current vehicle — `VehicleSwitcher`'s Button fires this per row.
    func selectVehicle(_ vehicle: Vehicle) {
        guard vehicle.id != currentVehicle?.id else { return }
        currentVehicle = vehicle
        analytics.track(.vehicleSwitched)
    }

    func paywallDidAppear(source: PaywallSource) {
        analytics.track(.paywallViewed(source: source))
    }

    /// Funnel exit — without it paywall conversion is uncomputable. Carries no outcome flag by
    /// design; see docs/developer/ANALYTICS_CONTRACT.md.
    func paywallDidDismiss(source: PaywallSource) {
        analytics.track(.paywallDismissed(source: source))
    }

    /// The launch impression `selectedTab`'s didSet cannot see (assigning the initial value
    /// runs no observer). Called once from ContentView's root task.
    func reportInitialScreen() {
        analytics.track(.screenViewed(screen: selectedTab.analyticsScreen))
    }
}

extension AppTab {
    var analyticsScreen: ScreenKind {
        switch self {
        case .dashboard: return .dashboard
        case .log: return .log
        case .garage: return .garage
        case .stats: return .stats
        case .settings: return .settings
        }
    }
}
