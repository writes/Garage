import Foundation
import Testing
import UIKit
@testable import Garage

@MainActor
struct ReceiptPreflighterTests {
    @Test func preflightImage_parseVariantBoundsToTheParseMaxDimension() throws {
        let data = try Self.solidImagePNGData(width: 4_000, height: 3_000)
        let preflight = try ReceiptPreflighter().preflightImage(data)
        let parseData = try #require(Data(base64Encoded: preflight.parseBase64))
        let decoded = try #require(UIImage(data: parseData))
        #expect(max(decoded.size.width, decoded.size.height) <= ReceiptPreflighter.parseMaxDimension)
    }

    @Test func preflightImage_parseVariantNormalizesRetinaScaleToPixels() throws {
        // A 1400x700pt image at 3x is 4200x2100 PIXELS; without the scale-1 re-render pass the
        // parse variant would upload well over the 1568px bound Anthropic's standard vision tier
        // expects (G4's retina trap).
        let retina = Self.solidImage(width: 1_400, height: 700, scale: 3)
        let data = try #require(retina.pngData())
        let preflight = try ReceiptPreflighter().preflightImage(data)
        let parseData = try #require(Data(base64Encoded: preflight.parseBase64))
        let decoded = try #require(UIImage(data: parseData))
        #expect(decoded.scale == 1)
        #expect(max(decoded.size.width, decoded.size.height) <= ReceiptPreflighter.parseMaxDimension)
    }

    @Test func preflightImage_outputsAreJPEGMagicBytes() throws {
        let data = try Self.solidImagePNGData(width: 800, height: 600)
        let preflight = try ReceiptPreflighter().preflightImage(data)
        let parseData = try #require(Data(base64Encoded: preflight.parseBase64))
        #expect(parseData.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(preflight.attachmentJPEG.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    /// F5: two independently named, differently-sized outputs — nothing downstream should be
    /// able to conflate the ephemeral parse copy with the persisted attachment copy.
    @Test func preflightImage_parseAndAttachmentVariantsAreDistinct() throws {
        let data = try Self.solidImagePNGData(width: 4_000, height: 3_000)
        let preflight = try ReceiptPreflighter().preflightImage(data)
        let parseData = try #require(Data(base64Encoded: preflight.parseBase64))
        #expect(parseData.count != preflight.attachmentJPEG.count)
        let parseImage = try #require(UIImage(data: parseData))
        let attachmentImage = try #require(UIImage(data: preflight.attachmentJPEG))
        #expect(max(parseImage.size.width, parseImage.size.height) <= ReceiptPreflighter.parseMaxDimension)
        #expect(
            max(attachmentImage.size.width, attachmentImage.size.height) <= AttachmentImageProcessor.maxDimension
        )
    }

    @Test func preflightImage_returnsInvalidImageForUndecodableData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        do {
            _ = try ReceiptPreflighter().preflightImage(garbage)
            Issue.record("Expected undecodable data to be rejected.")
        } catch let error as ReceiptPreflightError {
            #expect(error == .invalidImage)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func preflightPDF_reusesTheOilAnalysisCore() async throws {
        let url = try makeTemporaryPDF()
        defer { try? FileManager.default.removeItem(at: url) }
        let base64 = try await ReceiptPreflighter().preflightPDF(url: url)
        #expect(!base64.isEmpty)
    }

    @Test func preflightPDF_rejectsAFileOverTheSharedRawByteCap() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = Data("%PDF-".utf8)
        bytes.append(Data(repeating: 0, count: OilAnalysisPDFPreflighter.maxRawBytes + 1 - bytes.count))
        try bytes.write(to: url, options: .atomic)

        do {
            _ = try await ReceiptPreflighter().preflightPDF(url: url)
            Issue.record("Expected the byte above the raw cutoff to be rejected.")
        } catch let error as ReceiptPreflightError {
            #expect(error == .fileTooLarge)
        }
    }

    @Test func preflightPDF_rejectsANonPDFFile() async throws {
        let url = try makeTemporaryPDF(contents: Data("not-a-pdf".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await ReceiptPreflighter().preflightPDF(url: url)
            Issue.record("Expected a non-PDF file to be rejected.")
        } catch let error as ReceiptPreflightError {
            #expect(error == .invalidPDF)
        }
    }

    @Test func caps_matchThePlan() {
        #expect(ReceiptPreflighter.maxPages == 2)
        #expect(ReceiptPreflighter.maxImageBase64Bytes == 4 * 1024 * 1024)
    }

    private func makeTemporaryPDF(contents: Data = Data("%PDF-test".utf8)) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try contents.write(to: url, options: .atomic)
        return url
    }

    private static func solidImagePNGData(width: Int, height: Int) throws -> Data {
        try #require(solidImage(width: width, height: height).pngData())
    }

    /// scale 1 so width/height are PIXELS — the default renderer format uses the simulator's
    /// screen scale (3x), which would silently make every fixture 3x its stated size.
    private static func solidImage(width: Int, height: Int, scale: CGFloat = 1) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
