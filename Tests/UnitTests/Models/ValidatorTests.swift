import Foundation
import Testing
@testable import Garage

struct ValidatorTests {
    private let marchThird = Date(timeIntervalSince1970: 1_709_460_000) // 2024-03-03

    private func bounds(earlier: Int? = nil, later: Int? = nil) -> OdometerBounds {
        OdometerBounds(
            earlier: earlier.map { OdometerBoundary(reading: $0, entryDate: marchThird) },
            later: later.map { OdometerBoundary(reading: $0, entryDate: marchThird) }
        )
    }

    @Test func positiveInteger_rejectsZero() {
        #expect(
            Validators.positiveInteger("0", fieldName: "Mileage")
                == .validation("Mileage must be greater than zero.")
        )
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

    @Test func odometer_acceptsAReadingEqualToEitherBoundary() {
        #expect(Validators.odometer("50000", bounds: bounds(earlier: 50_000)) == nil)
        #expect(Validators.odometer("50000", bounds: bounds(later: 50_000)) == nil)
    }

    @Test func odometer_acceptsAnythingPositiveWhenThereIsNoNeighbouringEntry() {
        #expect(Validators.odometer("1", bounds: OdometerBounds()) == nil)
        #expect(Validators.odometer("999999", bounds: OdometerBounds()) == nil)
    }

    /// The whole point of the change: a reading below the vehicle's HIGHEST is fine, because that
    /// reading belongs to a later date. Only an earlier-dated entry can contradict it.
    @Test func odometer_acceptsAValueBetweenAnEarlierAndALaterEntry() {
        #expect(Validators.odometer("52000", bounds: bounds(earlier: 50_000, later: 60_000)) == nil)
    }

    /// The message names the conflicting record — the information needed to decide which of the
    /// two entries is actually the mistake — rather than restating a bare limit. The date goes
    /// through the app's one formatter (en_US: "Mar 3, 2024"), so this reads the same as the entry
    /// row it points at and does not flake on a differently-localed runner.
    @Test func odometer_rejectsAReadingBelowAnEarlierDatedEntryAndNamesIt() {
        let day = Formatters.shortDate.string(from: marchThird)
        let error = Validators.odometer("11999", bounds: bounds(earlier: 12_000))
        #expect(error == .validation("Odometer conflicts with the 12,000 mi entry on \(day)."))
    }

    @Test func odometer_rejectsAReadingAboveALaterDatedEntryAndNamesIt() {
        let day = Formatters.shortDate.string(from: marchThird)
        let error = Validators.odometer("60001", bounds: bounds(later: 60_000))
        #expect(error == .validation("Odometer conflicts with the 60,000 mi entry on \(day)."))
    }

    @Test func odometer_rejectsEmptyAndNonPositiveValuesBeforeConsultingTheBounds() {
        #expect(
            Validators.odometer("", bounds: bounds(earlier: 50_000))
                == .validation("Odometer must be greater than zero.")
        )
        #expect(
            Validators.odometer("0", bounds: OdometerBounds())
                == .validation("Odometer must be greater than zero.")
        )
    }

    @Test func nonEmpty_rejectsWhitespaceOnlyValues() {
        #expect(Validators.nonEmpty("  \n", fieldName: "Name") == .validation("Name is required."))
    }
}
