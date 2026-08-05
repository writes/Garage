import Testing
@testable import Garage

struct ReportSectionTests {
    @Test func allCases_includeTheOptionalPhotoAndReceiptSections() {
        #expect(ReportSection.allCases.contains(.photoGallery))
        #expect(ReportSection.allCases.contains(.receipts))
    }
}
