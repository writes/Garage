import FirebaseAppCheck
import FirebaseCore
import Foundation
import Observation

@MainActor
@Observable
final class AppIntegrityService {
    static let shared = AppIntegrityService()

    private(set) var isConfigured = false

    private init() {}

    func configure() {
        guard !isConfigured else { return }
        AppCheck.setAppCheckProviderFactory(providerFactory())
        isConfigured = true
        AppLogger.shared.info("App Check provider configured")
    }

    private func providerFactory() -> AppCheckProviderFactory {
#if DEBUG
        let isDebug = true
#else
        let isDebug = false
#endif
#if targetEnvironment(simulator)
        let isSimulator = true
#else
        let isSimulator = false
#endif
        let selection = Self.providerSelection(
            isDebug: isDebug,
            isSimulator: isSimulator,
            debugToken: ProcessInfo.processInfo.environment["FIRAAppCheckDebugToken"]
        )
        return selection == .debug ? AppCheckDebugProviderFactory() : GarageAppCheckProviderFactory()
    }

    nonisolated static func providerSelection(
        isDebug: Bool,
        isSimulator: Bool,
        debugToken: String?
    ) -> AppCheckProviderSelection {
        if isDebug && (isSimulator || debugToken?.isEmpty == false) {
            return .debug
        }
        return .device
    }
}

enum AppCheckProviderSelection: Equatable {
    case debug
    case device
}

final class GarageAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
    }
}
