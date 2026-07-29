import Foundation
import Testing
@testable import Garage

@MainActor
final class FakeReceiptPreflighter: ReceiptPreflighting {
    var imageResult: Result<ReceiptPagePreflight, Error> = .success(
        ReceiptPagePreflight(parseBase64: "cGFyc2U=", attachmentJPEG: Data([0xFF, 0xD8, 0xFF]))
    )
    var pdfResult: Result<String, Error> = .success("cGRmQmFzZTY0")
    private(set) var imageCallCount = 0
    private(set) var pdfCallCount = 0

    func preflightImage(_ data: Data) throws -> ReceiptPagePreflight {
        imageCallCount += 1
        return try imageResult.get()
    }

    func preflightPDF(url: URL) async throws -> String {
        pdfCallCount += 1
        return try pdfResult.get()
    }
}

@MainActor
final class SuspendedReceiptPreflighter: ReceiptPreflighting {
    private var continuation: CheckedContinuation<Result<String, Error>, Never>?
    private(set) var pdfCallCount = 0

    func preflightImage(_ data: Data) throws -> ReceiptPagePreflight {
        ReceiptPagePreflight(parseBase64: "cGFyc2U=", attachmentJPEG: Data([0xFF, 0xD8, 0xFF]))
    }

    func preflightPDF(url: URL) async throws -> String {
        pdfCallCount += 1
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        try Task.checkCancellation()
        return try result.get()
    }

    func completePDF(with result: Result<String, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
final class FakeReceiptService: ReceiptQuickAddCalling {
    var result: Result<ReceiptEntryProposal, Error>
    private(set) var lastImages: [String]?
    private(set) var lastPDFBase64: String?
    private(set) var callCount = 0

    init(result: Result<ReceiptEntryProposal, Error>) { self.result = result }

    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptEntryProposal {
        callCount += 1
        lastImages = images
        lastPDFBase64 = pdfBase64
        return try result.get()
    }
}

@MainActor
final class SuspendedReceiptService: ReceiptQuickAddCalling {
    private var continuation: CheckedContinuation<Result<ReceiptEntryProposal, Error>, Never>?
    private(set) var callCount = 0

    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptEntryProposal {
        callCount += 1
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func complete(with result: Result<ReceiptEntryProposal, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

let sampleReceiptProposal = ReceiptEntryProposal(
    entryType: .oilChange, odometerReading: 18_120, cost: 165, shopName: "Joe's Garage",
    isDiy: false, entryDate: nil, notes: "Synthetic blend", lineItems: ["Oil filter — $12.00"]
)

@MainActor
func makeReceiptCaptureViewModel(
    preflighter: any ReceiptPreflighting = FakeReceiptPreflighter(),
    service: any ReceiptQuickAddCalling = FakeReceiptService(result: .success(sampleReceiptProposal)),
    securityScope: any OilAnalysisPDFSecurityScopeAccessing = RecordingOilAnalysisSecurityScope(),
    analytics: AnalyticsSpy = AnalyticsSpy()
) -> ReceiptCaptureViewModel {
    analytics.setEnabled(true)
    return ReceiptCaptureViewModel(
        preflighter: preflighter, service: service, securityScope: securityScope,
        analytics: analytics, now: { Date(timeIntervalSince1970: 0) }
    )
}

@MainActor
func waitForReceiptPDFCall(_ preflighter: SuspendedReceiptPreflighter) async {
    for _ in 0 ..< 100 {
        if preflighter.pdfCallCount > 0 { return }
        await Task.yield()
    }
    Issue.record("Expected preflightPDF to be called.")
}

@MainActor
func waitForReceiptServiceCall(_ service: SuspendedReceiptService) async {
    for _ in 0 ..< 100 {
        if service.callCount > 0 { return }
        await Task.yield()
    }
    Issue.record("Expected proposeEntry to be called.")
}

@MainActor
func waitForReceiptPhase(
    _ viewModel: ReceiptCaptureViewModel, notEqualTo phase: ReceiptCapturePhase
) async {
    for _ in 0 ..< 100 {
        if viewModel.phase != phase { return }
        await Task.yield()
    }
    Issue.record("Expected the phase to move on from \(phase).")
}
