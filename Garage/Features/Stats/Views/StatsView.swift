import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = StatsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if !appState.isPro {
                        ProGateView(
                            title: "Stats are a Pro feature",
                            message: "Unlock MPG trends, cost breakdowns, and wear history charts for every vehicle.",
                            actionIdentifier: "stats.gate.cta"
                        ) {
                            router.present(.subscription(.stats))
                        }
                    } else if let error = viewModel.error {
                        ErrorBanner(error: error)
                    } else {
                        MPGTrendChart(entries: viewModel.entries)
                        CostBreakdownChart(entries: viewModel.entries)
                        WearHistoryChart(wearItems: viewModel.wearItems)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
            }
            .task(id: [appState.currentVehicle?.id, appState.isPro ? "pro" : "free"]) { await load() }
        }
    }

    private func load() async {
        guard appState.isPro, let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
