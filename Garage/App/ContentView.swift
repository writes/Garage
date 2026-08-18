import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    /// The app's ONLY haptic observer. It lives here, above the sheet presentation, because every
    /// event worth confirming dismisses its own host in the same transaction — see FeedbackCenter.
    @State private var feedback = FeedbackCenter.shared
    /// Held as @State so `.onChange(of:)` below observes pack swaps from EVERY path (server kill,
    /// bootstrap force, future levers) — not just the one server-override task in this file.
    @State private var designPackStore = DesignPackStore.shared

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
        // Fire-and-forget server registry refresh: the emergency kill switch must not wait
        // for a TestFlight build. On any effective change the pack is re-applied so a kill
        // restyles to control mid-session; failures keep the bundled/cached registry
        // (control-biased, always safe).
        .task {
            guard let override = await ExperimentConfigService.shared.fetchOverride() else { return }
            if ExperimentStore.shared.applyServerOverride(override) {
                DesignPackStore.shared.apply(arm: ExperimentStore.shared.arm(for: .designMegatest))
            }
        }
        .sheet(item: Binding(
            get: { router.activeSheet },
            set: { router.activeSheet = $0 }
        )) { sheet in
            sheetView(for: sheet)
        }
        // Counters start at 0 and only ever increase, so nothing fires on first render.
        .sensoryFeedback(.success, trigger: feedback.successCount)
        .sensoryFeedback(.warning, trigger: feedback.warningCount)
        .sensoryFeedback(.impact(weight: .light), trigger: feedback.lightImpactCount)
        // The appearance chokepoint: applied ONCE, at the root of the experiment surface, and read
        // inside a body so a mid-session kill restyles without a relaunch. Control's pack carries
        // nil — "no preference" — which is exactly today's behaviour, the system appearance.
        .preferredColorScheme(DesignPackStore.shared.pack.appearance)
        // A pack can drop the tab the user is standing on (Underhood surfaces no Stats/Settings
        // tab; the kill switch swaps back the other way). Normalizing here — once at appear for
        // the bootstrap-applied pack, and on EVERY subsequent swap — keeps `selectedTab` inside
        // the active structure no matter which path applied the pack.
        .onAppear { normalizeSelectedTab() }
        .onChange(of: designPackStore.pack) { normalizeSelectedTab() }
        // Sign-out/account-deletion swap the Group below to LoginView, but a router sheet
        // (Underhood's Settings, a paywall, an export) presents from THIS host and would stay
        // modal over the login screen until manually dismissed. No sheet belongs to a
        // signed-out session, in either arm.
        .onChange(of: appState.isAuthenticated) {
            if !appState.isAuthenticated {
                router.dismissSheet()
            }
        }
    }

    private var mainTabs: some View {
        let structure = DesignPackStore.shared.pack.structure
        return TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { newTab in
                if newTab == .record {
                    router.present(.entryPicker)
                    return
                }
                appState.selectedTab = newTab
            }
        )) {
            // The routing chokepoint: labels, symbols and ORDER come from the active pack's
            // structure (arm manifest §2.1). Control's structure is today's five tabs, in today's
            // order, with today's labels — the tab bar does not move.
            //
            // Every tab is built on FIRST SELECTION, not at launch: an eager TabView fired the
            // Dashboard, Log and Stats fetches concurrently before the owner had seen anything but
            // the Dashboard. Content is kept once built, so switching tabs never refetches.
            ForEach(structure.tabs) { item in
                lazyTab(item)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsFloatingAddButton {
                FloatingAddButton()
                    .padding(.trailing, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
            }
        }
        // The tab-bar token group (arm manifest §1). Control's fields are all nil, so this applies
        // nothing at all and the platform bar stays the platform bar.
        .garageTabBarChrome(DesignPackStore.shared.pack.components.tabBar)
        // Tab SWITCHES report via selectedTab's didSet; only the launch impression needs this.
        .onAppear { appState.reportInitialScreen() }
        // The app's ONE live vehicles listener. Hosted here, not in VehicleSwitcher (five screens
        // instantiate that), and not in AppState.bootstrap (a fetch is not a listener).
        .vehicleSyncHost()
    }

    /// Control keeps the overlay FAB on Dashboard/Log; Underhood moves Record into the tab bar.
    private var showsFloatingAddButton: Bool {
        let structure = DesignPackStore.shared.pack.structure
        guard !structure.visibleTabs.contains(.record) else { return false }
        return appState.selectedTab == .dashboard || appState.selectedTab == .log
    }

    private func normalizeSelectedTab() {
        let normalized = DesignPackStore.shared.pack.structure.normalizedTab(appState.selectedTab)
        if appState.selectedTab != normalized {
            appState.selectedTab = normalized
        }
    }

    private func lazyTab(_ item: DesignTabItem) -> some View {
        LazyTabContent(tab: item.tab, selection: appState.selectedTab) { root(for: item.tab) }
            .tag(item.tab)
            .tabItem { Label(item.title, systemImage: item.systemImage) }
    }

    /// The shipped root each tab identity hosts. Deliberately NOT part of the pack: every arm
    /// hosts the same view hierarchy per tab, so only the framing around these is themeable.
    /// Pack-driven titles and the settings accessory are applied INSIDE each root's own
    /// NavigationStack (`.designTabRootChrome`) — navigation chrome set from out here, above the
    /// stack, is silently ignored by SwiftUI.
    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView()
        case .log:
            LogView()
        case .garage:
            GarageView()
        case .stats:
            StatsView()
        case .settings:
            SettingsView()
        case .record:
            RecordTabPlaceholder()
        case .handover:
            HandoverTabView()
        }
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
        case .settings:
            // Event parity with control (§3 identical streams): a control user reaches Settings
            // by tab switch, which fires screenViewed via selectedTab.didSet. The Underhood
            // accessory presents it instead, so the SAME semantic event fires here. Control
            // never presents this sheet, so control's stream is untouched.
            SettingsView()
                .onAppear {
                    AnalyticsService.shared.track(.screenViewed(screen: .settings))
                }
        }
    }
}
