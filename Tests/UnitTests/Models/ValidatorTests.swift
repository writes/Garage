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

    @Test func positiveInteger_rejectsNegativeAndNonNumericValues() {
        #expect(
            Validators.positiveInteger("-1", fieldName: "Mileage")
                == .validation("Mileage must be greater than zero.")
        )
        #expect(
            Validators.positiveInteger("ten", fieldName: "Mileage")
                == .validation("Mileage must be greater than zero.")
        )
    }

    @Test func odometer_rejectsRegressiveAndEmptyValues() {
        #expect(
            Validators.odometer("49999", lastKnown: 50_000)
                == .validation("Odometer must be at least 50,000.")
        )
        #expect(Validators.nonEmpty("  \n", fieldName: "Name") == .validation("Name is required."))
        #expect(
            Validators.odometer("", lastKnown: nil)
                == .validation("Odometer must be greater than zero.")
        )
    }
}
