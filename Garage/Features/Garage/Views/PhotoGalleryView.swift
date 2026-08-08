import SwiftUI

struct PhotoGalleryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GalleryViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // There is no write path for gallery photos (GalleryService.save has no callers and
                // export hardcodes an empty photo list), so this screen is empty for EVERY user.
                // The copy says that as an unshipped feature rather than as a limitation of a
                // "beta" — the word was the app's only one, and Guideline 2.2 rejects builds that
                // present themselves as trials or demos.
                Text("Photo records aren't available yet.")
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
                    // Not "appear here when available": nothing can ever populate this list on the
                    // current build, so the old copy promised content that cannot arrive.
                    EmptyStateView(
                        title: "Gallery photo records are coming soon",
                        message: "Support for gallery photo records is coming in a future update.",
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
    /// was the gate BEFORE it, so the first visit flashed the empty state.
    private var isAwaitingLoad: Bool {
        guard let vehicle = appState.currentVehicle else { return viewModel.isLoading }
        return viewModel.isLoading || !viewModel.hasCompletedFirstLoad(for: vehicle.id)
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
