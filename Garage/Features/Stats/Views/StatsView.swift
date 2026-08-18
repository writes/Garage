import SwiftUI

/// The Stats TAB root (control arm): its own NavigationStack around the shared content.
struct StatsView: View {
    var body: some View {
        NavigationStack {
            StatsContent()
        }
    }
}

/// The whole Stats surface, stack-free, so it can be hosted BOTH ways the experiment needs:
/// wrapped in StatsView's own NavigationStack as control's tab root, and PUSHED inside the
/// Hood's stack by the Underhood arm's Trends row (arm manifest §2.2 — pushing StatsView itself
/// would nest a second NavigationStack). One body, byte-identical content in both arms.
struct StatsContent: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = StatsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if !appState.isPro {
                    ProGateView(
                        title: "Stats are a Pro feature",
                        message: "Unlock MPG trends, cost breakdowns, and wear history charts for every vehicle.",
                        actionIdentifier: "stats.gate.cta",
                        source: .stats
                    ) {
                        router.present(.subscription(.stats))
                    }
                } else if viewModel.isLoading || isAwaitingFirstLoad {
                    LoadingOverlay()
                } else if let error = viewModel.error {
                    // Without a retry this was the app's last dead-end error state: the screen
                    // reloads only on a vehicle/Pro change, so a transient failure stranded the
                    // tab until the user switched cars. Every sibling screen passes one.
                    ErrorBanner(error: error) { Task { await load() } }
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
                    // Below the charts, and absent entirely for a vehicle that has never seen
                    // a circuit. Stats walks the WHOLE history, so these counts are lifetime.
                    TrackDaySummaryCard(entries: viewModel.entries)
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

    /// Stats is built on first selection, so the frame before the first load resolves is real — and
    /// it must not read as "No stats data yet". Same tri-state pair DashboardView resolves: only a
    /// CONFIRMED zero-vehicle account (vehicle load completed, still no vehicle) is empty rather
    /// than loading.
    private var isAwaitingFirstLoad: Bool {
        guard appState.hasCompletedInitialVehicleLoad else { return true }
        guard let vehicle = appState.currentVehicle else { return false }
        return !viewModel.hasCompletedFirstLoad(for: vehicle.id)
    }

    private func load() async {
        guard appState.isPro, let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId, isPro: appState.isPro)
    }
}
