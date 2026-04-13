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
        AppCheck.setAppCheckProviderFactory(GarageAppCheckProviderFactory())
        isConfigured = true
        AppLogger.shared.info("App Check provider configured")
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
