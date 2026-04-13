import Testing
@testable import Garage

@MainActor
struct ExportViewModelTests {
    @Test func initialState_hasNoExportData() {
        let viewModel = ExportViewModel()

        #expect(viewModel.exportData == nil)
        #expect(viewModel.error == nil)
    }
}
