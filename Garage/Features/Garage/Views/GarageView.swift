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
                        """
                    ) {
                        router.present(.subscription)
                    }
                    .listRowSeparator(.hidden)
                } else {
                    NavigationLink("Photo Gallery") { PhotoGalleryView() }
                    NavigationLink("Wheel Gallery") { WheelGalleryView() }
                    NavigationLink("Spare Parts") { SparePartsView() }
                    NavigationLink("Detailing Log") { DetailingLogView() }
                    NavigationLink("Warranty & Recalls") { WarrantyRecallView() }
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
