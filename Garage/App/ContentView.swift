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
        // Exposure fires at the first render of the experiment surface (this whole view — the
        // login screen is inside the design test too). Pre-consent it is buffered by the
        // analytics gate, so it lands attributed to whichever identity later consents.
        .onAppear { ExperimentStore.shared.recordExposureIfNeeded(for: .designMegatest) }
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
            // Every tab is built on FIRST SELECTION, not at launch: an eager TabView fired the
            // Dashboard, Log and Stats fetches concurrently before the owner had seen anything but
            // the Dashboard. Content is kept once built, so switching tabs never refetches.
            lazyTab(.dashboard) { DashboardView() }
            lazyTab(.log) { LogView() }
            lazyTab(.garage) { GarageView() }
            lazyTab(.stats) { StatsView() }
            lazyTab(.settings) { SettingsView() }
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

    private func lazyTab(
        _ tab: AppTab, @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        LazyTabContent(tab: tab, selection: appState.selectedTab, content: content)
            .tag(tab)
            .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
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
        case .designSurvey:
            DesignSurveyView()
        }
    }
}
