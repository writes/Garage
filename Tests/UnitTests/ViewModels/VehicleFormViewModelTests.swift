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
        #expect(analytics.events == [.firstVehicleAdded])
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "first_vehicle_added")
        ])
    }
}
