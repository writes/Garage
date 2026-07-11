import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DashboardViewModel()
#if DEBUG
    @State private var demoStore = DemoSessionStore.shared
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    OdometerHeroCard(vehicle: appState.currentVehicle, hasActiveWarranty: viewModel.hasActiveWarranty)
                    RecallAlertBadge(openRecallCount: viewModel.openRecalls)

                    if viewModel.isLoading {
                        LoadingOverlay()
                    } else if let error = viewModel.error {
                        ErrorBanner(error: error, retry: { Task { await reload() } })
                    } else {
                        wearSection
                        remindersSection
                        RecentEntryFeed(entries: viewModel.recentEntries)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle("Dashboard")
            .background(Theme.Colors.background.ignoresSafeArea())
            .task(id: appState.currentVehicle?.id) { await reload() }
#if DEBUG
            .task(id: demoStore.revision) { await reload() }
#endif
            .onChange(of: appState.selectedTab) { _, selectedTab in
                guard selectedTab == .dashboard else { return }
                Task { await reload() }
            }
        }
    }

    private var wearSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Wear items")
                .font(Theme.Typography.title)
            if viewModel.wearItems.isEmpty {
                EmptyStateView(
                    title: "No wear data yet",
                    message: "Brake, tire, and clutch health will show up after the first relevant service entry.",
                    systemImage: "gauge.medium"
                )
            } else {
                ForEach(viewModel.wearItems) { item in
                    WearItemBar(label: item.type.label, percentage: item.percentage, rawValue: item.rawValue)
                }
                .garageCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remindersSection: some View {
        let reminders = displayedReminders
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Upcoming reminders")
                .font(Theme.Typography.title)
            if reminders.isEmpty {
                EmptyStateView(
                    title: "No reminders set",
                    message: "Create mileage or date-based reminders from Settings when you're ready.",
                    systemImage: "bell"
                )
            } else {
                ForEach(reminders) { reminder in
                    ReminderCard(reminder: reminder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayedReminders: [Reminder] {
#if DEBUG
        if AppRuntime.isLocalDemoMode, let vehicleId = appState.currentVehicle?.id {
        _ = demoStore.revision
        return demoStore.reminders(for: vehicleId).sorted {
            ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
        }
#endif
        return viewModel.upcomingReminders
    }

    private func reload() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.loadDashboard(vehicleId: vehicleId)
    }
}
