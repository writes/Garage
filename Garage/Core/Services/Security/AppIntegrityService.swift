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
#if DEBUG && targetEnvironment(simulator)
        return AppCheckDebugProviderFactory()
#elseif DEBUG
        if ProcessInfo.processInfo.environment["FIRAAppCheckDebugToken"]?.isEmpty == false {
            return AppCheckDebugProviderFactory()
        }

        return GarageAppCheckProviderFactory()
#else
        return GarageAppCheckProviderFactory()
#endif
    }
}

final class GarageAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
    }
}
