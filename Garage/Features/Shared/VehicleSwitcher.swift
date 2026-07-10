import SwiftUI

struct VehicleSwitcher: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            ForEach(appState.vehicles) { vehicle in
                Button(vehicle.displayName) {
                    appState.selectVehicle(vehicle)
                }
            }
            Divider()
            Button("Add Vehicle") {
                router.present(.vehicleForm)
            }
            .accessibilityIdentifier("vehicle.switcher.add")
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "car.2.fill")
                Text(appState.currentVehicle?.displayName ?? "Add your first vehicle")
                    .lineLimit(1)
                BadgeView(title: appState.syncStatus.label, color: badgeColor)
                    .accessibilityIdentifier("sync.badge")
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityLabel("Vehicle switcher")
        .accessibilityIdentifier("vehicle.switcher")
    }

    private var badgeColor: Color {
        switch appState.syncStatus {
        case .idle, .upToDate: return Theme.Colors.success
        case .syncing: return Theme.Colors.accent
        case .offline: return Theme.Colors.warning
        case .attentionNeeded: return Theme.Colors.error
        }
    }
}
