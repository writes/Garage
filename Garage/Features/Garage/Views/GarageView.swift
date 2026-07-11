import SwiftUI

struct GarageView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            List {
                if !appState.isPro {
                    ProGateView(
                        title: "Garage tools are part of Pro",
                        message: """
                        Gallery, wheel photos, spare parts, detailing,
                        warranty, and recalls are unlocked with Pro.
                        """,
                        actionIdentifier: "garage.gate.cta"
                    ) {
                        router.present(.subscription)
                    }
                    .listRowSeparator(.hidden)
                } else {
                    NavigationLink("Photo Gallery") { PhotoGalleryView() }
                        .accessibilityIdentifier("garage.gallery")
                    NavigationLink("Wheel Gallery") { WheelGalleryView() }
                        .accessibilityIdentifier("garage.wheels")
                    NavigationLink("Spare Parts") { SparePartsView() }
                        .accessibilityIdentifier("garage.parts")
                    NavigationLink("Detailing Log") { DetailingLogView() }
                        .accessibilityIdentifier("garage.detailing")
                    NavigationLink("Warranty & Recalls") { WarrantyRecallView() }
                        .accessibilityIdentifier("garage.warranty")
                }
            }
            .navigationTitle("Garage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
            }
        }
    }
}
