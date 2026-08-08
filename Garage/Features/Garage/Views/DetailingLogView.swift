import SwiftUI

struct DetailingLogView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DetailingViewModel()
    @State private var isShowingForm = false

    var body: some View {
        List {
            if isAwaitingLoad {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("garage.detailing.loading")
            } else if let error = viewModel.error {
                // Previously absent: a failed fetch left "No detailing history yet" on screen,
                // reporting an empty log for a car that may have a full one.
                ErrorBanner(error: error) {
                    Task { await load() }
                }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("garage.detailing.error")
            } else if viewModel.records.isEmpty {
                EmptyStateView(
                    title: "No detailing history yet",
                    message: """
                    Keep paint correction, coating, PPF, tint, and cosmetic work
                    separate from mechanical maintenance.
                    """,
                    systemImage: "sparkles"
                )
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.records) { record in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(record.title).font(Theme.Typography.headline)
                        Text(record.serviceType.displayName).font(Theme.Typography.caption)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Detailing")
        .toolbar {
            Button("Add Record") { isShowingForm = true }
                .accessibilityIdentifier("detailing.add")
        }
        .task(id: appState.currentVehicle?.id) { await load() }
        .sheet(isPresented: $isShowingForm) { DetailingFormView() }
        .onChange(of: isShowingForm) { _, isPresented in
            guard !isPresented else { return }
            Task { await load() }
        }
    }

    /// A vehicle is selected but its first load has not resolved yet — the frame that used to read
    /// as "No detailing history yet". Only a screen with NO vehicle skips straight to the empty
    /// state, because nothing will ever be fetched for it.
    private var isAwaitingLoad: Bool {
        guard let vehicle = appState.currentVehicle else { return viewModel.isLoading }
        return viewModel.isLoading || !viewModel.hasCompletedFirstLoad(for: vehicle.id)
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
