import Foundation
import Testing
@testable import Garage

@MainActor
struct OilAnalysisPDFPreflighterTests {
    @Test func clientLimit_reservesCallableEnvelopeHeadroom_andRejectsTheNextRawByte() throws {
        #expect(OilAnalysisPDFPreflighter.maxPDFBase64Bytes == 9 * 1024 * 1024)
        #expect(OilAnalysisPDFPreflighter.maxRawBytes == 7_077_888)
        #expect(
            OilAnalysisPDFPreflighter.maxRawBytes ==
                3 * (OilAnalysisPDFPreflighter.maxPDFBase64Bytes / 4)
        )
        #expect(
            OilAnalysisPDFPreflightError.fileTooLarge.appError ==
                .validation("Choose a PDF smaller than 6.75 MiB.")
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = Data("%PDF-".utf8)
        bytes.append(Data(repeating: 0, count: OilAnalysisPDFPreflighter.maxRawBytes + 1 - bytes.count))
        try bytes.write(to: url, options: .atomic)

        do {
            _ = try OilAnalysisPDFPreflighter.readBoundedBase64(from: url)
            Issue.record("Expected the byte above the raw cutoff to be rejected.")
        } catch let error as OilAnalysisPDFPreflightError {
            #expect(error == .fileTooLarge)
        }
    }

    @Test func encodedLengthGuard_acceptsClientLimit_andRejectsTheNextByte() throws {
        try OilAnalysisPDFPreflighter.validateEncodedLength(
            String(repeating: "A", count: OilAnalysisPDFPreflighter.maxPDFBase64Bytes)
        )
        let oversized = String(repeating: "A", count: OilAnalysisPDFPreflighter.maxPDFBase64Bytes + 1)
        do {
            try OilAnalysisPDFPreflighter.validateEncodedLength(oversized)
            Issue.record("Expected the encoded-length guard to reject oversized base64.")
        } catch let error as OilAnalysisPDFPreflightError {
            #expect(error == .fileTooLarge)
        }
    }

    @Test func preflight_readsAnAlreadyAuthorizedDocument_withoutAcquiringAnotherScopeLease() async throws {
        let url = try makeTemporaryPDF()
        defer { try? FileManager.default.removeItem(at: url) }
        let preflighter = OilAnalysisPDFPreflighter()

        _ = try await preflighter.preflight(url: url)
    }

    @Test func preflight_keepsBoundedValidationAfterConsent() async throws {
        let url = try makeTemporaryPDF(contents: Data("not-a-pdf".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let preflighter = OilAnalysisPDFPreflighter()

        do {
            _ = try await preflighter.preflight(url: url)
            Issue.record("Expected an invalid PDF to be rejected.")
        } catch let error as OilAnalysisPDFPreflightError {
            #expect(error == .invalidPDF)
        }
    }

    private func makeTemporaryPDF(contents: Data = Data("%PDF-test".utf8)) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try contents.write(to: url, options: .atomic)
        return url
    }
}
