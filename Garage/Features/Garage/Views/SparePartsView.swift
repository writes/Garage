import SwiftUI

struct SparePartsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = PartsViewModel()
    @State private var isShowingForm = false

    var body: some View {
        List {
            if viewModel.parts.isEmpty {
                EmptyStateView(
                    title: "No spare parts on hand",
                    message: """
                    Track parts you own before they are installed so you can keep
                    inventory tied to each car.
                    """,
                    systemImage: "shippingbox"
                )
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.parts) { part in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(part.name).font(Theme.Typography.headline)
                        Text("\(part.quantity)x • \(part.condition.rawValue)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Spare Parts")
        .toolbar {
            Button("Add Part") { isShowingForm = true }
        }
        .task { await load() }
        .sheet(isPresented: $isShowingForm) {
            SparePartFormView()
        }
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
