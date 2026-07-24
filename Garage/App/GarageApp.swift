import FirebaseCore
import FirebaseAuth
import FirebaseAnalytics
import GoogleSignIn
import RevenueCat
import SwiftData
import SwiftUI

@main
struct GarageApp: App {
    @State private var appState: AppState
    @State private var router: AppRouter
    private let bootstrapMode: BootstrapMode
    private let modelContainer = GarageApp.makeModelContainer()

    init() {
        let bootstrapMode = Self.resolveBootstrapMode()
        self.bootstrapMode = bootstrapMode

        switch bootstrapMode {
        case .uiTest, .localDemo, .localSetupRequired:
            let appState = Self.makeNonProductionAppState(for: bootstrapMode)
            _appState = State(initialValue: appState)
            // Review finding: "not yet loaded" must never read as "confirmed zero vehicles" — an
            // existing signed-in user with vehicles would otherwise get misrouted to vehicle
            // creation on cold launch, before bootstrap's first fetch/listener snapshot lands.
            // The gate only fires once a load has actually completed and found zero vehicles.
            _router = State(initialValue: AppRouter(
                hasVehicles: { !appState.hasCompletedInitialVehicleLoad || !appState.vehicles.isEmpty }
            ))
            return
        case .production:
            break
        }

        // XcodeGen regenerates this plist from protected project.yml properties, so an
        // Info.plist collection key would not be durable. Apply Firebase's persisted
        // runtime override before any Firebase configuration can produce an event.
        Analytics.setAnalyticsCollectionEnabled(false)
        AppIntegrityService.shared.configure()

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        Purchases.configure(withAPIKey: Secrets.revenueCatAPIKey)
        let appState = AppState()
        _appState = State(initialValue: appState)
        // See the matching comment in the non-production branch above: the gate must not treat
        // "not yet loaded" as "confirmed zero vehicles".
        _router = State(initialValue: AppRouter(
            hasVehicles: { !appState.hasCompletedInitialVehicleLoad || !appState.vehicles.isEmpty }
        ))
    }

    var body: some Scene {
        WindowGroup {
            // The design system defines no dark-appearance asset variants, so dark mode renders
            // broken (white text on white surfaces). Lock the app to light until a real dark
            // palette is designed. This covers presented sheets too.
            Group {
                switch bootstrapMode {
                case .uiTest:
                    UITestHarnessView()
                case .localDemo:
                    ContentView()
                        .environment(appState)
                        .environment(router)
                        .modelContainer(modelContainer)
                case .localSetupRequired:
                    LocalSetupRequiredView()
                case .production:
                    ContentView()
                        .environment(appState)
                        .environment(router)
                        .modelContainer(modelContainer)
                        .onOpenURL { url in
                            if GIDSignIn.sharedInstance.handle(url) {
                                return
                            }

                            _ = Auth.auth().canHandle(url)
                        }
                }
            }
            .preferredColorScheme(.light)
        }
    }
}

private extension GarageApp {
    enum BootstrapMode {
        case production
        case uiTest
        case localDemo
        case localSetupRequired
    }

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("UI_TEST_MODE")
    }

    static func resolveBootstrapMode() -> BootstrapMode {
        if isUITesting {
            return .uiTest
        }

        if AppRuntime.isLocalDemoMode {
            return .localDemo
        }

        return FirebaseOptions.defaultOptions() == nil ? .localSetupRequired : .production
    }

    static func makeNonProductionAppState(for mode: BootstrapMode) -> AppState {
        let authService: AuthService
        switch mode {
        case .localDemo:
            authService = .localDemo
        case .uiTest, .localSetupRequired, .production:
            authService = .uiTest
        }
        return AppState(
            authService: authService,
            vehicleService: .uiTest,
            purchaseService: .uiTest,
            syncService: .shared,
            analytics: NoopAnalyticsService(),
            // Explicit noop: these modes run before (or without) FirebaseApp.configure, and
            // FirebaseCrashReporter touches Crashlytics.crashlytics() on setEnabled — the same
            // pre-configure launch-crash class the deleteAccount service hit.
            crashReporter: NoopCrashReporter()
        )
    }

    static func makeModelContainer() -> ModelContainer {
        do {
            _ = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            AppLogger.shared.error("Failed to prepare application support directory: \(error.localizedDescription)")
        }

        do {
            return try ModelContainer(for: SyncQueueItem.self, DraftEntry.self)
        } catch {
            AppLogger.shared.error("Persistent SwiftData container failed: \(error.localizedDescription)")

            do {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(
                    for: SyncQueueItem.self,
                    DraftEntry.self,
                    configurations: configuration
                )
            } catch {
                preconditionFailure("Failed to create any SwiftData container: \(error.localizedDescription)")
            }
        }
    }
}

private struct LocalSetupRequiredView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ContentUnavailableView(
                        "Garage needs Firebase setup",
                        systemImage: "wrench.and.screwdriver.fill",
                        description: Text(
                            """
                            The app did not find a bundled GoogleService-Info.plist, so live services were not started.
                            """
                        )
                    )

                    Group {
                        Text("Next steps")
                            .font(.headline)
                        Text("1. Add `GoogleService-Info.plist` to the Garage app target.")
                        Text("2. Place the file under `Garage/Resources/` in this workspace.")
                        Text("3. Rebuild and launch again.")
                        Text(
                            """
                            RevenueCat and Firebase-backed features stay disabled until the Firebase config is present.
                            """
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
            .navigationTitle("Setup Required")
        }
    }
}

private struct UITestHarnessView: View {
    var body: some View {
        Text("Garage UI Test Mode Ready")
            .padding()
            .accessibilityIdentifier("ui-test-ready")
    }
}
