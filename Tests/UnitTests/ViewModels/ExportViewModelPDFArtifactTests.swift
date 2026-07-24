import Foundation
import Testing
@testable import Garage

/// PDF export-share audit finding (paid PDF could not be saved/shared): buildPDF now writes the
/// report to a temp file, exposed via authorizedPDFURL(for:) for ExportView's ShareLink. Split
/// out from ExportViewModelTests.swift/ExportSessionIsolationTests to stay under the file cap.
@MainActor
struct ExportViewModelPDFArtifactTests {
    @Test func buildPDF_writesARetrievableFileAtTheFactoryURLAndCleansUpOnDiscard() async throws {
        let url = tempPDFURL("artifact")
        let viewModel = ExportViewModel(entryService: EntryService(testEntries: [entryA]), pdfURLFactory: { url })

        await viewModel.buildPDF(vehicle: vehicleA, authorization: { pdfAuthorizationA })

        let retrievedURL = try #require(viewModel.authorizedPDFURL(for: pdfAuthorizationA))
        #expect(retrievedURL == url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let onDisk = try Data(contentsOf: url)
        #expect(onDisk == viewModel.authorizedPDFData(for: pdfAuthorizationA))

        viewModel.discardExportArtifacts()
        #expect(viewModel.authorizedPDFURL(for: pdfAuthorizationA) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unauthorizedCallerCannotRetrieveTheFileEvenWhileItExistsOnDisk() async throws {
        let url = tempPDFURL("unauthorized")
        let viewModel = ExportViewModel(entryService: EntryService(testEntries: [entryA]), pdfURLFactory: { url })

        await viewModel.buildPDF(vehicle: vehicleA, authorization: { pdfAuthorizationA })

        #expect(viewModel.authorizedPDFURL(for: nil) == nil)
        #expect(viewModel.authorizedPDFURL(for: .init(session: sessionB)) == nil)
        viewModel.discardExportArtifacts()
    }

    @Test func sessionChangeDeletesTheRetainedPDFFileTooNotJustTheInMemoryData() async throws {
        let url = tempPDFURL("session-change")
        let viewModel = ExportViewModel(entryService: EntryService(testEntries: [entryA]), pdfURLFactory: { url })
        viewModel.sessionChanged(to: sessionA)

        await viewModel.buildPDF(vehicle: vehicleA, authorization: { pdfAuthorizationA })
        #expect(FileManager.default.fileExists(atPath: url.path))

        viewModel.sessionChanged(to: sessionB)
        #expect(viewModel.authorizedPDFURL(for: pdfAuthorizationA) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func abandonedPDFFileFromAPriorLaunchIsSweptOnInit() {
        let abandoned = FileManager.default.temporaryDirectory
            .appending(path: "garage-record-pdf-test-\(UUID().uuidString).pdf")
        #expect(FileManager.default.createFile(atPath: abandoned.path, contents: Data()))
        _ = ExportViewModel()
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
    }

    private var vehicleA: Vehicle {
        Vehicle(
            id: "vehicle-a", userId: "user-a", nickname: "A", make: "Garage",
            model: "Test", year: 2026, currentOdometer: 1
        )
    }
    private var sessionA: ExportSessionAuthorization {
        .init(authenticationRevision: 1, subscriptionRevision: 3, vehicleID: "vehicle-a", vehicleOwnerID: "user-a")
    }
    private var sessionB: ExportSessionAuthorization {
        .init(authenticationRevision: 2, subscriptionRevision: 5, vehicleID: "vehicle-b", vehicleOwnerID: "user-b")
    }
    private var pdfAuthorizationA: PDFExportAuthorization { .init(session: sessionA) }
    private var entryA: FirestoreEntry {
        FirestoreEntry(
            id: "entry-a", vehicleId: "vehicle-a", userId: "user-a",
            entryType: .maintenance, entryDate: .now, odometerReading: 1,
            cost: nil, isDiy: nil, shopName: nil, notes: "account-a",
            attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }
    private func tempPDFURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "garage-export-pdf-\(label)-\(UUID().uuidString).pdf")
    }
}
