import SwiftUI

struct WheelGalleryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GalleryViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Text("Record details only. Photo files cannot be added, viewed, saved, or exported in this beta.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("garage.wheels.notice")

                if isAwaitingLoad {
                    LoadingOverlay()
                        .accessibilityIdentifier("garage.wheels.loading")
                } else if let error = viewModel.error {
                    ErrorBanner(error: error) {
                        Task { await load() }
                    }
                    .accessibilityIdentifier("garage.wheels.error")
                } else if wheelPhotos.isEmpty {
                    EmptyStateView(
                        title: "No wheel records yet",
                        message: "Existing wheel record details appear here when available.",
                        systemImage: "circle.grid.2x2"
                    )
                } else {
                    ForEach(wheelPhotos) { photo in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(photo.title).font(Theme.Typography.headline)
                            Text(photo.wheelBrand ?? "Wheel brand not set").font(Theme.Typography.body)
                            Text(photo.tireComboAtTimeOfPhoto ?? "Tire combo not set").font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .garageCard()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle("Wheel Records")
        .task(id: appState.currentVehicle?.id) { await load() }
    }

    private var wheelPhotos: [GalleryPhoto] {
        viewModel.photos.filter { $0.section == .wheel }
    }

    /// See PhotoGalleryView.isAwaitingLoad — same gate, same reason.
    private var isAwaitingLoad: Bool {
        viewModel.isLoading || (appState.currentVehicle != nil && !viewModel.hasCompletedFirstLoad)
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
