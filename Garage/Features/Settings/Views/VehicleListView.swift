import SwiftUI

struct VehicleListView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var vehiclePendingDeletion: Vehicle?
    @State private var isDeleting = false
    @State private var deletionErrorMessage: String?

    var body: some View {
        List {
            ForEach(appState.vehicles) { vehicle in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(vehicle.displayName).font(Theme.Typography.headline)
                    Text("\(vehicle.currentOdometer.formatted()) mi").font(Theme.Typography.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(vehicle.displayName)
                .accessibilityValue("\(vehicle.currentOdometer.formatted()) miles")
                .accessibilityIdentifier("vehicle.row.\(vehicle.id)")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        vehiclePendingDeletion = vehicle
                    }
                    .accessibilityIdentifier("vehicle.delete.\(vehicle.id)")
                }
            }
        }
        .navigationTitle("Vehicles")
        .toolbar {
            Button("Add Vehicle") {
                router.present(.vehicleForm)
            }
            .accessibilityIdentifier("vehicle.list.add")
        }
        .confirmationDialog(
            "Delete \(vehiclePendingDeletion?.displayName ?? "vehicle")?",
            isPresented: Binding(
                get: { vehiclePendingDeletion != nil },
                set: { if !$0 { vehiclePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Vehicle and All Records", role: .destructive) {
                guard let vehicle = vehiclePendingDeletion, !isDeleting else { return }
                vehiclePendingDeletion = nil
                isDeleting = true
                Task {
                    defer { isDeleting = false }
                    do {
                        try await appState.deleteVehicle(vehicle)
                    } catch {
                        deletionErrorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) { vehiclePendingDeletion = nil }
        } message: {
            Text(
                "This permanently deletes the vehicle and every service record, photo, " +
                "and reminder attached to it. This cannot be undone."
            )
        }
        .alert(
            "Could Not Delete Vehicle",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "")
        }
    }
}
