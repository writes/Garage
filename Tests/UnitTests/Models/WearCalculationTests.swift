import Testing
@testable import Garage

struct WearCalculationTests {
    @Test func wearItemType_labelsRemainStable() {
        #expect(WearItemType.frontBrakePads.label == "Front Brake Pads")
        #expect(WearItemType.rearTires.label == "Rear Tires")
    }
}
