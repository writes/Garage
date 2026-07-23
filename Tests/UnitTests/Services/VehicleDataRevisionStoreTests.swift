import Testing
@testable import Garage

@MainActor
struct VehicleDataRevisionStoreTests {
    @Test func revision_defaultsToZeroForAnUnseenVehicle() {
        let store = VehicleDataRevisionStore()

        #expect(store.revision(for: "vehicle") == 0)
    }

    @Test func bump_incrementsOnlyTheTargetedVehicle() {
        let store = VehicleDataRevisionStore()

        store.bump(vehicleId: "vehicle-a")
        store.bump(vehicleId: "vehicle-a")
        store.bump(vehicleId: "vehicle-b")

        #expect(store.revision(for: "vehicle-a") == 2)
        #expect(store.revision(for: "vehicle-b") == 1)
        #expect(store.revision(for: "vehicle-c") == 0)
    }

    @Test func sharedInstance_isASingleton() {
        #expect(VehicleDataRevisionStore.shared === VehicleDataRevisionStore.shared)
    }
}
