import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if appState.isAuthenticated {
                mainTabs
            } else {
                LoginView()
            }
        }
        .task(id: appState.authenticationStateID) {
            await appState.bootstrap()
        }
        .sheet(item: Binding(
            get: { router.activeSheet },
            set: { router.activeSheet = $0 }
        )) { sheet in
            sheetView(for: sheet)
        }
    }

    private var mainTabs: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )) {
            DashboardView()
                .tag(AppTab.dashboard)
                .tabItem { Label(AppTab.dashboard.rawValue, systemImage: AppTab.dashboard.icon) }

            LogView()
                .tag(AppTab.log)
                .tabItem { Label(AppTab.log.rawValue, systemImage: AppTab.log.icon) }

            GarageView()
                .tag(AppTab.garage)
                .tabItem { Label(AppTab.garage.rawValue, systemImage: AppTab.garage.icon) }

            StatsView()
                .tag(AppTab.stats)
                .tabItem { Label(AppTab.stats.rawValue, systemImage: AppTab.stats.icon) }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem { Label(AppTab.settings.rawValue, systemImage: AppTab.settings.icon) }
        }
        .overlay(alignment: .bottomTrailing) {
            if appState.selectedTab == .dashboard || appState.selectedTab == .log {
                FloatingAddButton()
                    .padding(.trailing, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
            }
        }
        // Tab SWITCHES report via selectedTab's didSet; only the launch impression needs this.
        .onAppear { appState.reportInitialScreen() }
        // The app's ONE live vehicles listener. Hosted here, not in VehicleSwitcher (five screens
        // instantiate that), and not in AppState.bootstrap (a fetch is not a listener).
        .vehicleSyncHost()
    }

    @ViewBuilder
    private func sheetView(for sheet: AppRouter.Sheet) -> some View {
        switch sheet {
        case .entryPicker:
            EntryTypePicker()
        case .voiceQuickAdd:
            VoiceQuickAddView()
        case .receiptCapture:
            ReceiptCaptureView()
        case .entryForm(let type):
            EntryFormFactoryView(entryType: type)
        case .vehicleForm:
            VehicleFormView()
        case .export:
            ExportView()
        case .subscription(let source):
            SubscriptionView(source: source)
        }
    }
}
