import Testing
@testable import Garage

struct EntryDetailFormattingTests {
    @Test func humanizesCamelCaseStorageKeys() {
        #expect("bestLapTime".humanizedFieldLabel == "Best Lap Time")
        #expect("eventType".humanizedFieldLabel == "Event Type")
        #expect("oilGrade".humanizedFieldLabel == "Oil Grade")
        #expect("quantityQuarts".humanizedFieldLabel == "Quantity Quarts")
        #expect("venue".humanizedFieldLabel == "Venue")
    }

    @Test func humanizesSnakeAndKebabKeys() {
        #expect("pad_compound".humanizedFieldLabel == "Pad Compound")
        #expect("where-purchased".humanizedFieldLabel == "Where Purchased")
        #expect("".humanizedFieldLabel == "")
    }

    @Test func rendersValuesForUsersNotDebugDescriptions() {
        #expect(CodableValue.string("Willow Springs").displayString == "Willow Springs")
        #expect(CodableValue.string("1:34.821").displayString == "1:34.821")
        #expect(CodableValue.double(10.5).displayString == "10.5")
        #expect(CodableValue.double(10.0).displayString == "10")
        #expect(CodableValue.int(8).displayString == "8")
        #expect(CodableValue.bool(true).displayString == "Yes")
        #expect(CodableValue.bool(false).displayString == "No")
        #expect(CodableValue.null.displayString == "—")
        #expect(CodableValue.array([AnyCodable("A"), AnyCodable("B")]).displayString == "A, B")
    }
}
