import Foundation
import UIKit

enum ReceiptPreflightError: Error, Equatable, Sendable {
    case invalidImage
    case invalidFile
    case unreadableFile
    case fileTooLarge
    case invalidPDF

    var appError: AppError {
        switch self {
        case .invalidImage:
            return .validation("Choose a valid receipt photo.")
        case .unreadableFile:
            return .unknown("Couldn't read that file. Please choose it again.")
        case .invalidFile, .invalidPDF:
            return .validation("Choose a valid receipt PDF.")
        case .fileTooLarge:
            return .validation("Choose a smaller file.")
        }
    }

    fileprivate init(_ pdfError: OilAnalysisPDFPreflightError) {
        switch pdfError {
        case .invalidFile: self = .invalidFile
        case .unreadableFile: self = .unreadableFile
        case .fileTooLarge: self = .fileTooLarge
        case .invalidPDF: self = .invalidPDF
        }
    }
}

/// One photographed/imported receipt page, preflighted into the two independent outputs the
/// capture flow needs (F5 — the judged defect this fixes, so nothing downstream conflates them):
/// a small JPEG sent to Claude to parse, and a separate, higher-res JPEG staged as an entry
/// attachment if the user keeps the page and is Pro.
struct ReceiptPagePreflight: Equatable, Sendable {
    /// 1568px longest edge, JPEG q0.85, base64-encoded — sized to Haiku's standard-resolution
    /// vision tier (G4); this variant is ephemeral and is never uploaded as an attachment.
    let parseBase64: String
    /// AttachmentImageProcessor's existing 2048px/q0.8 bound, reused verbatim so this file
    /// introduces no second downsampling policy for the persisted copy.
    let attachmentJPEG: Data
}

@MainActor
protocol ReceiptPreflighting: Sendable {
    func preflightImage(_ data: Data) throws -> ReceiptPagePreflight
    func preflightPDF(url: URL) async throws -> String
}

/// Mirrors OilAnalysisPDFPreflighter's shape for the PDF path (calls its validated-base64 core
/// directly rather than duplicating the chunked-read/magic-byte logic) and AttachmentPicker's
/// precedent for images (downsampling runs synchronously on the main actor — cheap enough for a
/// single photo, unlike the PDF's chunked multi-MB read).
struct ReceiptPreflighter: ReceiptPreflighting {
    /// Longest edge for the PARSE variant only — distinct from AttachmentImageProcessor
    /// .maxDimension (2048), which stays the attachment bound.
    static let parseMaxDimension: CGFloat = 1_568
    static let parseJPEGQuality: CGFloat = 0.85
    static let maxPages = 2
    /// Mirrors receiptQuickAdd.ts's per-image ≤4 MiB base64 validation (plan §4) — failing here
    /// means the user sees an error before the metered callable is ever invoked.
    static let maxImageBase64Bytes = 4 * 1024 * 1024

    func preflightImage(_ data: Data) throws -> ReceiptPagePreflight {
        guard let image = UIImage(data: data) else { throw ReceiptPreflightError.invalidImage }
        let parseImage = AttachmentImageProcessor.resized(image, maxDimension: Self.parseMaxDimension)
        guard let parseJPEG = parseImage.jpegData(compressionQuality: Self.parseJPEGQuality) else {
            throw ReceiptPreflightError.invalidImage
        }
        let parseBase64 = parseJPEG.base64EncodedString()
        guard parseBase64.utf8.count <= Self.maxImageBase64Bytes else {
            throw ReceiptPreflightError.fileTooLarge
        }
        // Reuses the ONE decode above (image) rather than re-decoding `data` — F5/perf finding:
        // the parse and attachment variants are two independent resize passes off the same
        // source UIImage, not two full JPEG/PNG decodes.
        guard let attachmentJPEG = AttachmentImageProcessor.downsampledJPEG(from: image) else {
            throw ReceiptPreflightError.invalidImage
        }
        return ReceiptPagePreflight(parseBase64: parseBase64, attachmentJPEG: attachmentJPEG)
    }

    /// Security-scope access is owned by the CALLER (ReceiptCaptureViewModel), exactly like
    /// OilAnalysisPDFPreflighter — this type has no access dependency and cannot read a document
    /// before consent/lease acquisition.
    func preflightPDF(url: URL) async throws -> String {
        try Task.checkCancellation()
        let worker = Task.detached(priority: nil) { @Sendable () throws -> String in
            try Task.checkCancellation()
            do {
                return try OilAnalysisPDFPreflighter.readValidatedBase64(from: url)
            } catch let error as OilAnalysisPDFPreflightError {
                throw ReceiptPreflightError(error)
            }
        }
        return try await withTaskCancellationHandler(operation: {
            try await worker.value
        }, onCancel: {
            worker.cancel()
        })
    }
}
