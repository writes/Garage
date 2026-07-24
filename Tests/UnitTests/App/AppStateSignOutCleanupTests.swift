import Foundation
import Testing
@testable import Garage

/// FIX 2 / FIX 7 review findings: AppState.signOut() (the single choke point BOTH plain sign-out
/// and account deletion funnel through — see SettingsView.deleteAccount()) never cancelled
/// scheduled local reminder notifications or cleared QuickLook preview temp-file residue. The
/// next person on the same device could otherwise inherit a prior user's reminders or leftover
/// attachment bytes. Split out of AppStateTests.swift to stay under the file cap.
@MainActor
private final class SignOutFakeScheduler: NotificationScheduling {
    private(set) var cancelAllCallCount = 0

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState { .authorized }
    func schedule(_: ReminderNotificationRequest) async {}
    func cancel(id _: String) {}
    func cancelAll() { cancelAllCallCount += 1 }
}

@MainActor
private final class SignOutNoOpProfileStore: ProfileStore {
    func loadProfile(uid _: String) async throws -> ProfileFields? { nil }
    func saveProfile(_: ProfileFields, uid _: String) async throws {}
}

@MainActor
struct AppStateSignOutCleanupTests {
    @Test func signOut_cancelsAllScheduledReminderNotifications() {
        let scheduler = SignOutFakeScheduler()
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: "user", analytics: analytics),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: NoopCrashReporter(),
            profileStore: SignOutNoOpProfileStore(),
            notificationCoordinator: ReminderNotificationCoordinator(scheduler: scheduler)
        )

        state.signOut()

        #expect(scheduler.cancelAllCallCount == 1)
    }

    @Test func signOut_removesAnyPendingPreviewTempFile() throws {
        let url = try PDFPreviewTempFile.write(Data([0x25, 0x50, 0x44, 0x46]), filename: "receipt.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: "user", analytics: analytics),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: NoopCrashReporter(),
            profileStore: SignOutNoOpProfileStore(),
            notificationCoordinator: ReminderNotificationCoordinator(scheduler: SignOutFakeScheduler())
        )

        state.signOut()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
