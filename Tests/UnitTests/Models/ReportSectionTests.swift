import Testing
@testable import Garage

struct ReportSectionTests {
    @Test func allCases_includeVehicleHistoryPlaceholder() {
        #expect(ReportSection.allCases.contains(.vehicleHistoryPlaceholder))
        #expect(ReportSection.allCases.contains(.photoGallery))
        #expect(ReportSection.allCases.contains(.receipts))
    }
}
