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
                    //
                    // Audit finding (false empty state): keying that CTA off `vehicles.isEmpty`
                    // alone made "the first load has not landed yet" render as "you own no
                    // vehicles", so EVERY returning owner got a flash of "Add Your First Vehicle"
                    // on cold launch. hasCompletedInitialVehicleLoad is the tri-state that tells
                    // the two apart — the same guard AppRouter's vehicle gate already uses.
                    switch DashboardVehicleState.resolve(
                        hasCompletedInitialVehicleLoad: appState.hasCompletedInitialVehicleLoad,
                        isVehicleListEmpty: appState.vehicles.isEmpty
                    ) {
                    case .awaitingFirstLoad:
                        LoadingOverlay()
                    case .noVehicles:
                        zeroVehicleState
                    case .ready:
                        loadedVehicleBody
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

    @ViewBuilder
    private var loadedVehicleBody: some View {
        OdometerHeroCard(
            vehicle: appState.currentVehicle, hasActiveWarranty: viewModel.hasActiveWarranty
        )
        RecallAlertBadge(openRecallCount: viewModel.openRecalls)

        if viewModel.isLoading {
            LoadingOverlay()
        } else if let error = viewModel.error {
            ErrorBanner(error: error, retry: { Task { await reload() } })
        } else if viewModel.hasNoHistory {
            // A vehicle with no entries would otherwise stack FOUR negative panels — needs-
            // attention, wear, reminders, recent activity — on the very first screen after adding
            // a car. Four "nothing here" cards in a row read as a broken app rather than a new
            // one. One next step instead.
            firstEntryState
        } else {
            // Above wear and reminders: the only section that says what the car needs rather than
            // replaying what the owner already entered.
            MaintenanceDueCard(
                items: viewModel.maintenanceDue,
                historyDepth: DashboardViewModel.historyDepth
            )
            wearSection
            remindersSection
            RecentEntryFeed(entries: viewModel.recentEntries)
        }
    }

    /// The activation moment: one vehicle, no history. Mirrors zeroVehicleState below — a single
    /// explicit next step rather than a column of empty sections.
    private var firstEntryState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                title: "Log your first service",
                message: "Add an oil change, a fill-up, or whatever you did last. "
                    + "Wear, reminders and cost per mile all build from your entries.",
                systemImage: "wrench.and.screwdriver"
            )
            PrimaryButton(title: "Add First Entry", systemImage: "plus") {
                router.present(.entryPicker)
            }
            .accessibilityIdentifier("dashboard.firstEntry.cta")
        }
        .garageCard()
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
                remindersEmptyState
            } else {
                ForEach(reminders) { reminder in
                    ReminderCard(reminder: reminder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pairs an EmptyStateView with a PrimaryButton like firstEntryState and zeroVehicleState — the
    /// only dashboard empty state that was still pure prose with nothing to tap.
    ///
    /// The button switches TABS rather than presenting a form, because there is no reminder route
    /// to present: AppRouter.Sheet has no reminder case, and ReminderConfigView's single call site
    /// is SettingsView's "Reminder Settings" NavigationLink. Adding a sheet route would mean a new
    /// AppRouter case plus a new FormKind (a new analytics value) for a two-tap path that already
    /// exists — so the copy names the destination instead of the button over-promising a form.
    private var remindersEmptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                title: "No reminders set",
                message: "Reminders live in Settings → Reminder Settings. "
                    + "Set one by mileage or date and the next service stops being something you have to remember.",
                systemImage: "bell"
            )
            PrimaryButton(title: "Go to Settings", systemImage: "gearshape") {
                appState.selectedTab = .settings
            }
            .accessibilityIdentifier("dashboard.reminders.cta")
        }
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

/// Which of the three vehicle-keyed dashboard bodies to render. Extracted from the view so the
/// distinction that actually matters is unit-testable: an empty `vehicles` array means "you own
/// no vehicles" ONLY once a load has completed. Before that it means nothing at all, and treating
/// it as zero is what flashed "Add Your First Vehicle" at owners with a full garage.
enum DashboardVehicleState: Equatable {
    case awaitingFirstLoad
    case noVehicles
    case ready

    static func resolve(hasCompletedInitialVehicleLoad: Bool, isVehicleListEmpty: Bool) -> Self {
        guard hasCompletedInitialVehicleLoad else { return .awaitingFirstLoad }
        return isVehicleListEmpty ? .noVehicles : .ready
    }
}
