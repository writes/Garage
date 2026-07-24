import Foundation
import Testing
@testable import Garage

/// Covers the "no unbounded accumulation" discipline behind EntryDetailView's QuickLook preview
/// flow (AttachmentDetailRow.swift): at most one file lives under the preview temp directory at
/// any time, and removeAll() leaves nothing behind.
struct PDFPreviewTempFileTests {
    @Test func write_persistsTheGivenBytesUnderTheReturnedURL() throws {
        let bytes = Data([0x25, 0x50, 0x44, 0x46])
        let url = try PDFPreviewTempFile.write(bytes, filename: "receipt.pdf")
        defer { PDFPreviewTempFile.removeAll() }

        #expect(try Data(contentsOf: url) == bytes)
        #expect(url.lastPathComponent == "receipt.pdf")
    }

    @Test func write_removesAnyPreviouslyWrittenPreviewFile() throws {
        let first = try PDFPreviewTempFile.write(Data([0x01]), filename: "first.pdf")
        defer { PDFPreviewTempFile.removeAll() }

        let second = try PDFPreviewTempFile.write(Data([0x02]), filename: "second.pdf")

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func removeAll_deletesTheWrittenFile() throws {
        let url = try PDFPreviewTempFile.write(Data([0x01]), filename: "receipt.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))

        PDFPreviewTempFile.removeAll()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func removeAll_isANoopWhenNothingWasEverWritten() {
        PDFPreviewTempFile.removeAll()
        PDFPreviewTempFile.removeAll()
    }
}
