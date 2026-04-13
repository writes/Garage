import FirebaseCore
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
        case .uiTest:
            _appState = State(initialValue: AppState(
                authService: .uiTest,
                vehicleService: .uiTest,
                purchaseService: .uiTest,
                syncService: .shared
            ))
            _router = State(initialValue: AppRouter())
            return
        case .localSetupRequired:
            _appState = State(initialValue: AppState(
                authService: .uiTest,
                vehicleService: .uiTest,
                purchaseService: .uiTest,
                syncService: .shared
            ))
            _router = State(initialValue: AppRouter())
            return
        case .production:
            break
        }

        AppIntegrityService.shared.configure()

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        Purchases.configure(withAPIKey: Secrets.revenueCatAPIKey)
        _appState = State(initialValue: AppState())
        _router = State(initialValue: AppRouter())
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapMode {
            case .uiTest:
                UITestHarnessView()
            case .localSetupRequired:
                LocalSetupRequiredView()
            case .production:
                ContentView()
                    .environment(appState)
                    .environment(router)
                    .modelContainer(modelContainer)
            }
        }
    }
}

private extension GarageApp {
    enum BootstrapMode {
        case production
        case uiTest
        case localSetupRequired
    }

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("UI_TEST_MODE")
    }

    static func resolveBootstrapMode() -> BootstrapMode {
        if isUITesting {
            return .uiTest
        }

        return FirebaseOptions.defaultOptions() == nil ? .localSetupRequired : .production
    }

    static func makeModelContainer() -> ModelContainer {
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
                            "The app did not find a bundled GoogleService-Info.plist, so live services were not started."
                        )
                    )

                    Group {
                        Text("Next steps")
                            .font(.headline)
                        Text("1. Add `GoogleService-Info.plist` to the Garage app target.")
                        Text("2. Place the file under `Garage/Resources/` in this workspace.")
                        Text("3. Rebuild and launch again.")
                        Text("RevenueCat and Firebase-backed features stay disabled until the Firebase config is present.")
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
