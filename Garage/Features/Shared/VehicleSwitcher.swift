import SwiftUI

/// Presentation only. This view is instantiated by five screens, so the live vehicles listener it
/// used to start per instance now lives in `VehicleSyncHost`, hosted once above the TabView.
struct VehicleSwitcher: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var syncService = SyncService.shared

    var body: some View {
        Menu {
            ForEach(appState.vehicles) { vehicle in
                Button {
                    appState.selectVehicle(vehicle)
                } label: {
                    // Monogram + colour, not the manufacturer emblem: those are registered
                    // trademarks and shipping them in a paid tier is trademark use in commerce.
                    // This also distinguishes two cars from the same marque, which an emblem cannot.
                    Label {
                        Text(vehicle.displayName)
                    } icon: {
                        VehicleBadge(vehicle: vehicle, size: 24)
                    }
                }
            }
            Divider()
            // Preflight, not enforcement — VehicleService still validates server-side. This only
            // stops a free user from filling the entire form and waiting for a round trip just to
            // be told "no" by a banner whose one button is "Try Again".
            if appState.canAddVehicle {
                Button("Add Vehicle") {
                    router.present(.vehicleForm)
                }
                .accessibilityIdentifier("vehicle.switcher.add")
            } else if appState.vehicleLimitUpgradeWouldHelp {
                Button("Add Vehicle (Pro)") {
                    router.present(.subscription(.vehicleLimit))
                }
                .accessibilityIdentifier("vehicle.switcher.add")
            } else {
                // A Pro user at their own ceiling: no purchase resolves this, so offering the
                // paywall would be selling something they already own.
                Button("Vehicle limit reached") {}
                    .disabled(true)
                    .accessibilityIdentifier("vehicle.switcher.add")
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let current = appState.currentVehicle {
                    VehicleBadge(vehicle: current, size: 22)
                } else {
                    Image(systemName: "car.2.fill")
                }
                Text(appState.currentVehicle?.displayName ?? "Add your first vehicle")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                BadgeView(
                    title: syncService.presentationState.label,
                    color: badgeColor
                )
                    .accessibilityIdentifier("sync.badge")
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityLabel("Vehicle switcher")
        .accessibilityValue(appState.currentVehicle?.displayName ?? "No vehicle selected")
        .accessibilityIdentifier("vehicle.switcher")
    }

    private var badgeColor: Color {
        switch syncService.presentationState {
        case .upToDate: return Theme.Colors.success
        case .syncing, .checkingSync: return Theme.Colors.accent
        case .savedOnThisIPhone, .offlineCachedData: return Theme.Colors.warning
        case .needsAttention: return Theme.Colors.error
        }
    }
}
