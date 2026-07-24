import Testing
@testable import Garage

struct FuelEntryTests {
    @Test func calculatedMPG_dividesDistanceByGallons() {
        let mpg = FuelEntry.calculatedMPG(currentOdometer: 12_400, previousOdometer: 12_100, gallons: 10)
        #expect(mpg == 30)
    }

    @Test func calculatedMPG_isNilOnAFirstEverFillUp() {
        // Modeled by the caller never having a previous fuel entry to pass in; the pure helper
        // itself only sees a distance/gallons pair, so this documents the zero-distance edge.
        #expect(FuelEntry.calculatedMPG(currentOdometer: 12_100, previousOdometer: 12_100, gallons: 10) == nil)
    }

    @Test func calculatedMPG_isNilForNegativeDistance() {
        #expect(FuelEntry.calculatedMPG(currentOdometer: 12_000, previousOdometer: 12_100, gallons: 10) == nil)
    }

    @Test func calculatedMPG_isNilForZeroOrNegativeGallons() {
        #expect(FuelEntry.calculatedMPG(currentOdometer: 12_400, previousOdometer: 12_100, gallons: 0) == nil)
        #expect(FuelEntry.calculatedMPG(currentOdometer: 12_400, previousOdometer: 12_100, gallons: -5) == nil)
    }
}
