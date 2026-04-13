import SwiftUI

struct DetailingLogView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DetailingViewModel()
    @State private var isShowingForm = false

    var body: some View {
        List {
            if viewModel.records.isEmpty {
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
                        Text(record.serviceType.rawValue).font(Theme.Typography.caption)
                    }
                }
            }
        }
        .navigationTitle("Detailing")
        .toolbar {
            Button("Add Record") { isShowingForm = true }
        }
        .task { await load() }
        .sheet(isPresented: $isShowingForm) { DetailingFormView() }
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
