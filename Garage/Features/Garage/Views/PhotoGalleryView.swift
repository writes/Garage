import SwiftUI

struct PhotoGalleryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GalleryViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Text("Record details only. Photo files cannot be added, viewed, saved, or exported in this beta.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("garage.gallery.notice")

                if isAwaitingLoad {
                    LoadingOverlay()
                        .accessibilityIdentifier("garage.gallery.loading")
                } else if let error = viewModel.error {
                    ErrorBanner(error: error) {
                        Task { await load() }
                    }
                    .accessibilityIdentifier("garage.gallery.error")
                } else if mainPhotos.isEmpty {
                    EmptyStateView(
                        title: "No gallery records yet",
                        message: "Existing gallery record details appear here when available.",
                        systemImage: "photo.stack"
                    )
                } else {
                    ForEach(mainPhotos) { photo in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(photo.title).font(Theme.Typography.headline)
                            if let caption = photo.caption, caption.isNotEmpty {
                                Text(caption).font(Theme.Typography.body)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .garageCard()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle("Gallery Records")
        .task(id: appState.currentVehicle?.id) { await load() }
        // Weekly feature-usage matrix; gallery has no other event (see UninstrumentedFeature).
        .onAppear { AnalyticsService.shared.track(.featureUsed(feature: .gallery)) }
    }

    private var mainPhotos: [GalleryPhoto] {
        viewModel.photos.filter { $0.section == .main }
    }

    /// See DetailingLogView.isAwaitingLoad. The error branch already existed here; what was missing
    /// was the gate BEFORE it, so the first visit flashed "No gallery records yet".
    private var isAwaitingLoad: Bool {
        viewModel.isLoading || (appState.currentVehicle != nil && !viewModel.hasCompletedFirstLoad)
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
