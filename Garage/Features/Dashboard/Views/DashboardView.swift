import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = DashboardViewModel()
#if DEBUG
    @State private var demoStore = DemoSessionStore.shared
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Audit finding (zero-vehicle activation dead end): a fresh account's
                    // dashboard used to render an "empty" but otherwise normal layout (hero card
                    // reading "No vehicle selected", empty wear/reminders sections) with no
                    // actionable next step. Replace the whole body with one explicit CTA instead.
                    if appState.vehicles.isEmpty {
                        zeroVehicleState
                    } else {
                        OdometerHeroCard(
                            vehicle: appState.currentVehicle, hasActiveWarranty: viewModel.hasActiveWarranty
                        )
                        RecallAlertBadge(openRecallCount: viewModel.openRecalls)

                        if viewModel.isLoading {
                            LoadingOverlay()
                        } else if let error = viewModel.error {
                            ErrorBanner(error: error, retry: { Task { await reload() } })
                        } else {
                            // Above wear and reminders: this is the only section that says what
                            // the car needs rather than replaying what the owner already entered.
                            MaintenanceDueCard(
                                items: viewModel.maintenanceDue,
                                historyDepth: DashboardViewModel.historyDepth
                            )
                            wearSection
                            remindersSection
                            RecentEntryFeed(entries: viewModel.recentEntries)
                        }
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
            // The FAB opens the entry form as a sheet on ContentView, so saving from the Dashboard
            // tab changes neither the vehicle id nor the selected tab — nothing above fires, and
            // the user's first entry appeared to vanish: hero odometer, wear, reminders and Recent
            // activity all stayed as they were. LogView has carried this exact modifier all along.
            // Safe on every dismissal (including a cancel or the paywall) because loadDashboard is
            // revision-gated, so a dismissal with no write behind it is a no-op.
            .onChange(of: router.activeSheet) { _, activeSheet in
                guard activeSheet == nil else { return }
                Task { await reload() }
            }
        }
    }

    private var zeroVehicleState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                title: "Add Your First Vehicle",
                message: "Garage tracks service history, wear, and reminders per vehicle. Add one to get started.",
                systemImage: "car.fill"
            )
            PrimaryButton(title: "Add Your First Vehicle", systemImage: "plus") {
                router.present(.vehicleForm)
            }
            .accessibilityIdentifier("dashboard.addFirstVehicle")
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
