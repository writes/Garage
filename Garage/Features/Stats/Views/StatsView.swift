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
                    } else if viewModel.isLoading {
                        LoadingOverlay()
                    } else if let error = viewModel.error {
                        ErrorBanner(error: error)
                    } else if !viewModel.hasContent {
                        EmptyStateView(
                            title: "No stats data yet",
                            message: "Add fuel, maintenance, or wear entries to start seeing trends here.",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .accessibilityIdentifier("stats.emptyState")
                    } else {
                        // Leads the screen: it is the only figure here derived from the data
                        // rather than replayed from it, and it is what the owner came to find out.
                        OwnershipCostCard(entries: viewModel.entries)
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
