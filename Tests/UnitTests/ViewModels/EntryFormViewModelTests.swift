import Testing
@testable import Garage

@MainActor
struct EntryFormViewModelTests {
    @Test func odometerValidation_rejectsLowerThanLast() {
        let viewModel = EntryFormViewModel()
        viewModel.lastKnownOdometer = 50_000
        viewModel.odometerReading = "49000"

        let result = viewModel.validateOdometer()

        #expect(result == false)
        #expect(viewModel.error == .validation("Odometer must be at least 50,000."))
    }

    @Test func odometerValidation_acceptsHigherThanLast() {
        let viewModel = EntryFormViewModel()
        viewModel.lastKnownOdometer = 50_000
        viewModel.odometerReading = "50150"

        let result = viewModel.validateOdometer()

        #expect(result == true)
    }
}
