import Testing
@testable import Garage

struct ValidatorTests {
    @Test func positiveInteger_rejectsZero() {
        #expect(
            Validators.positiveInteger("0", fieldName: "Mileage")
                == .validation("Mileage must be greater than zero.")
        )
    }

    @Test func odometer_acceptsEqualLastKnown() {
        #expect(Validators.odometer("50000", lastKnown: 50_000) == nil)
    }
}
