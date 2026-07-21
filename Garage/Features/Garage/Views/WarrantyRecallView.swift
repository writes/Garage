import SwiftUI

struct WarrantyRecallView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = WarrantyViewModel()

    var body: some View {
        List {
            Section("Warranties") {
                if viewModel.warranties.isEmpty {
                    Text("No warranty records yet")
                } else {
                    ForEach(viewModel.warranties) { warranty in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(warranty.warrantyType.rawValue.capitalized).font(Theme.Typography.headline)
                            Text(
                                warranty.expirationDate?.shortDisplay
                                    ?? warranty.coverageEnd?.shortDisplay
                                    ?? "No expiration date"
                            )
                                .font(Theme.Typography.caption)
                        }
                    }
                }
            }

            Section("Recalls") {
                if viewModel.recalls.isEmpty {
                    Text("No recall records yet")
                } else {
                    ForEach(viewModel.recalls) { recall in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(recall.title).font(Theme.Typography.headline)
                            Text(recall.status.rawValue).font(Theme.Typography.caption)
                                .foregroundStyle(
                                    recall.status == .outstanding
                                        ? Theme.Colors.error
                                        : Theme.Colors.textSecondary
                                )
                        }
                    }
                }
            }
        }
        .navigationTitle("Warranty & Recalls")
        .task(id: appState.currentVehicle?.id) { await load() }
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
