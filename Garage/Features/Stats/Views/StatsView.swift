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
                    } else if !viewModel.hasContent {
                        EmptyStateView(
                            title: "No stats data yet",
                            message: "Add fuel, service, or wear entries to start seeing trends here.",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .accessibilityIdentifier("stats.emptyState")
                    } else {
                        MPGTrendChart(entries: viewModel.entries)
                        CostBreakdownChart(entries: viewModel.entries)
                        WearHistoryChart(wearItems: viewModel.wearItems)
                        if viewModel.entries.count == 100 {
                            Text("Based on the most recent 100 entries.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .accessibilityIdentifier("stats.recentEntriesCaption")
                        }
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
        await viewModel.load(vehicleId: vehicleId, isPro: appState.isPro)
    }
}
