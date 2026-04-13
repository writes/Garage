import SwiftUI

struct PhotoGalleryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GalleryViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if mainPhotos.isEmpty {
                    EmptyStateView(
                        title: "No gallery photos yet",
                        message: """
                        Use this section for beauty shots, progress photos, and
                        anything you want in the story of the car.
                        """,
                        systemImage: "photo.stack"
                    )
                } else {
                    ForEach(mainPhotos) { photo in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(photo.title).font(Theme.Typography.headline)
                            if let caption = photo.caption, caption.isNotEmpty {
                                Text(caption).font(Theme.Typography.body)
                            }
                            BadgeView(title: photo.includeInExport ? "Included in export" : "Hidden from export")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .garageCard()
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle("Photo Gallery")
        .task { await load() }
    }

    private var mainPhotos: [GalleryPhoto] {
        viewModel.photos.filter { $0.section == .main }
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
