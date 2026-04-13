import SwiftUI

struct WheelGalleryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GalleryViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if wheelPhotos.isEmpty {
                    EmptyStateView(
                        title: "No wheel gallery yet",
                        message: """
                        Save wheel and tire combo photos here with fitment details
                        for future reference and exports.
                        """,
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
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle("Wheel Gallery")
        .task { await load() }
    }

    private var wheelPhotos: [GalleryPhoto] {
        viewModel.photos.filter { $0.section == .wheel }
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
