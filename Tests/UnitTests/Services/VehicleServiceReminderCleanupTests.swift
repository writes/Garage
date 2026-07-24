import Testing
@testable import Garage

/// FIX 2 review finding: nothing cancelled a vehicle's scheduled local reminder notifications
/// when it was deleted — reminders are purged server-side via recursiveDelete, never through
/// ReminderService/ReminderNotificationCoordinator. VehicleService.deleteVehicle now calls a
/// best-effort injected seam (reminderNotificationCancelInvoker, mirroring purgeInvoker's own
/// resolved-inside-the-closure style) before proceeding. Split out of VehicleServiceTests.swift
/// to stay under the file cap.
@MainActor
struct VehicleServiceReminderCleanupTests {
    @Test func deleteVehicle_invokesTheReminderCancellationSeamWithTheDeletedVehiclesID() async throws {
        var cancelledVehicleIDs: [String] = []
        let service = VehicleService(
            testVehicles: [vehicle(id: "existing")],
            purchaseService: PurchaseService(testIsPro: false),
            reminderNotificationCancelInvoker: { cancelledVehicleIDs.append($0) }
        )

        try await service.deleteVehicle(vehicle(id: "existing"))

        #expect(cancelledVehicleIDs == ["existing"])
    }

    @Test func deleteVehicle_defaultSeamIsANoopWhenNoInvokerIsInjected() async throws {
        let service = VehicleService(
            testVehicles: [vehicle(id: "existing")], purchaseService: PurchaseService(testIsPro: false)
        )

        try await service.deleteVehicle(vehicle(id: "existing"))

        #expect(try await service.fetchVehicles().isEmpty)
    }

    /// Regression guard: the default (production) seam self-gates on `mode == .live` — the call
    /// site in VehicleService+Deletion.swift is deliberately unconditional (reached from every
    /// branch, for hermetic testability above), so this closure is what keeps `VehicleService
    /// .uiTest` (GarageApp's non-production bootstrap singleton) from ever touching
    /// ReminderService/Firestore during a real UI-test run. `.uiTest` mode's deleteVehicle was
    /// already a complete no-op before this fix; this must still hold afterward.
    @Test func deleteVehicle_uiTestModeSingletonStaysANoOpAndNeverTouchesLiveReminderService() async throws {
        try await VehicleService.uiTest.deleteVehicle(vehicle(id: "irrelevant"))
    }

    private func vehicle(id: String) -> Vehicle {
        Vehicle(id: id, userId: "user", nickname: id, make: "Garage", model: "Test", year: 2026, currentOdometer: 1)
    }
}
