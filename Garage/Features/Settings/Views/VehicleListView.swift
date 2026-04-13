import SwiftUI

struct VehicleListView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            ForEach(appState.vehicles) { vehicle in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(vehicle.displayName).font(Theme.Typography.headline)
                    Text("\(vehicle.currentOdometer.formatted()) mi").font(Theme.Typography.caption)
                }
            }
        }
        .navigationTitle("Vehicles")
        .toolbar {
            Button("Add Vehicle") {
                router.present(.vehicleForm)
            }
        }
    }
}
