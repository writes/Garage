import Testing
@testable import Garage

@MainActor
struct VehicleFormViewModelTests {
    @Test func firstVehicleSave_emitsFirstVehicleEventWithSchemaVersion() async {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = VehicleFormViewModel(
            vehicleService: VehicleService(
                testVehicles: [],
                purchaseService: PurchaseService(testIsPro: false)
            ),
            analytics: analytics
        )
        viewModel.nickname = "Test Car"
        viewModel.make = "Garage"
        viewModel.model = "Coupe"
        viewModel.year = "2026"
        viewModel.currentOdometer = "1200"

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(analytics.events == [.vehicleAdded(vehicleCount: 1), .firstVehicleAdded])
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "vehicle_added", parameters: [.vehicleCount(1)]),
            AnalyticsEventDefinition(name: "first_vehicle_added")
        ])
    }

    @Test func secondVehicleSave_emitsVehicleAddedWithCountButNotFirstVehicleEvent() async {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let existing = Vehicle(
            id: "existing", userId: "", nickname: "Existing", make: "Garage", model: "Sedan",
            year: 2020, currentOdometer: 500, fuelType: .premium93, displayOrder: 0
        )
        let viewModel = VehicleFormViewModel(
            vehicleService: VehicleService(
                testVehicles: [existing],
                // Pro is required: the free tier's 1-vehicle cap would reject this save before
                // any analytics could fire, which is exactly what the first run of this test
                // proved by failing.
                purchaseService: PurchaseService(testIsPro: true)
            ),
            analytics: analytics
        )
        viewModel.nickname = "Second Car"
        viewModel.make = "Garage"
        viewModel.model = "Coupe"
        viewModel.year = "2026"
        viewModel.currentOdometer = "1200"

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(analytics.events == [.vehicleAdded(vehicleCount: 2)])
    }
}
