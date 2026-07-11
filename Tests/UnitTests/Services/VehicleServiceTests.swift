import Testing
@testable import Garage

@MainActor
struct VehicleServiceTests {
    @Test func freeUser_isBlockedAtVehicleCap() async {
        let service = VehicleService(
            testVehicles: [vehicle(id: "existing")],
            purchaseService: PurchaseService(testIsPro: false)
        )

        do {
            _ = try await service.createVehicle(vehicle(id: "new"))
            Issue.record("Expected the free vehicle cap to reject the second vehicle")
        } catch {
            #expect(error as? AppError == .vehicleLimitReached)
        }
    }

    @Test func freeUser_canCreateVehicleImmediatelyBelowCap() async throws {
        let service = VehicleService(
            testVehicles: [],
            purchaseService: PurchaseService(testIsPro: false)
        )

        let created = try await service.createVehicle(vehicle(id: "first"))
        let vehicles = try await service.fetchVehicles()

        #expect(created.id == "first")
        #expect(vehicles.map(\.id) == ["first"])
    }

    @Test func proUser_canCreateVehicleImmediatelyBelowCap() async throws {
        let service = VehicleService(
            testVehicles: (0..<(Constants.maxProVehicles - 1)).map { vehicle(id: "existing-\($0)") },
            purchaseService: PurchaseService(testIsPro: true)
        )

        _ = try await service.createVehicle(vehicle(id: "fifth"))
        let vehicles = try await service.fetchVehicles()

        #expect(vehicles.count == Constants.maxProVehicles)
    }

    @Test func proUser_isBlockedAtVehicleCap() async {
        let service = VehicleService(
            testVehicles: (0..<Constants.maxProVehicles).map { vehicle(id: "existing-\($0)") },
            purchaseService: PurchaseService(testIsPro: true)
        )

        do {
            _ = try await service.createVehicle(vehicle(id: "sixth"))
            Issue.record("Expected the Pro vehicle cap to reject the sixth vehicle")
        } catch {
            #expect(error as? AppError == .vehicleLimitReached)
        }
    }

    private func vehicle(id: String) -> Vehicle {
        Vehicle(
            id: id,
            userId: "user",
            nickname: id,
            make: "Garage",
            model: "Test",
            year: 2026,
            currentOdometer: 1
        )
    }
}
