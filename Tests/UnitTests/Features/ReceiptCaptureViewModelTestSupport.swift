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
        return try result.get()
    }

    func completePDF(with result: Result<String, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
final class FakeReceiptService: ReceiptQuickAddCalling {
    var result: Result<ReceiptProposalResult, Error>
    var quotaStatusResult: Result<ReceiptQuotaSnapshot, Error> = .success(.fixture)
    var confirmResult: Result<ReceiptQuotaSnapshot, Error> = .success(.fixture)
    private(set) var lastImages: [String]?
    private(set) var lastPDFBase64: String?
    private(set) var callCount = 0
    private(set) var quotaStatusCallCount = 0
    private(set) var confirmTokens: [String] = []

    init(result: Result<ReceiptProposalResult, Error>) { self.result = result }

    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptProposalResult {
        callCount += 1
        lastImages = images
        lastPDFBase64 = pdfBase64
        return try result.get()
    }

    func confirmScan(token: String) async throws -> ReceiptQuotaSnapshot {
        confirmTokens.append(token)
        return try confirmResult.get()
    }

    var reconcileResult: Result<ReceiptQuotaSnapshot, Error> = .success(.fixture)
    private(set) var quotaStatusTransactionIDs: [String?] = []
    private(set) var reconcileTransactionIDs: [String] = []

    /// Runs inside the await — lets a test flip signed-in identity mid-call (lease tests).
    var onQuotaStatus: (() -> Void)?

    func quotaStatus(transactionID: String?) async throws -> ReceiptQuotaSnapshot {
        quotaStatusCallCount += 1
        quotaStatusTransactionIDs.append(transactionID)
        onQuotaStatus?()
        return try quotaStatusResult.get()
    }

    func reconcileCreditPurchase(transactionID: String) async throws -> ReceiptQuotaSnapshot {
        reconcileTransactionIDs.append(transactionID)
        return try reconcileResult.get()
    }
}

@MainActor
final class SuspendedReceiptService: ReceiptQuickAddCalling {
    private var continuation: CheckedContinuation<Result<ReceiptProposalResult, Error>, Never>?
    private(set) var callCount = 0

    func proposeEntry(
        images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async throws -> ReceiptProposalResult {
        callCount += 1
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func complete(with result: Result<ReceiptProposalResult, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func confirmScan(token: String) async throws -> ReceiptQuotaSnapshot {
        throw AppError.unknown("Confirmation is unavailable in this suspended fake.")
    }

    func quotaStatus(transactionID: String?) async throws -> ReceiptQuotaSnapshot {
        throw AppError.unknown("Quota status is unavailable in this suspended fake.")
    }

    func reconcileCreditPurchase(transactionID: String) async throws -> ReceiptQuotaSnapshot {
        throw AppError.unknown("Reconcile is unavailable in this suspended fake.")
    }
}

let sampleReceiptProposal = ReceiptEntryProposal(
    entryType: .oilChange, odometerReading: 18_120, cost: 165, shopName: "Joe's Garage",
    isDiy: false, entryDate: nil, notes: "Synthetic blend", lineItems: ["Oil filter — $12.00"]
)

extension ReceiptQuotaSnapshot {
    static let fixture = ReceiptQuotaSnapshot(
        entitlement: .free, scanRemaining: 20, scanCeiling: 20,
        confirmedRemaining: 5, confirmedAllowance: 5, resetAt: nil
    )
}

@MainActor
func makeReceiptCaptureViewModel(
    preflighter: any ReceiptPreflighting = FakeReceiptPreflighter(),
    service: any ReceiptQuickAddCalling = FakeReceiptService(result: .success(.init(
        proposal: sampleReceiptProposal, token: nil, quota: nil
    ))),
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
