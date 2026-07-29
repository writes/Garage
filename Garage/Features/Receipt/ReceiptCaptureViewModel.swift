import Foundation
import Observation

// Receipt state, failure policy, and task result wrappers live in ReceiptCaptureTypes.swift —
// split out to stay under the file-length cap.

/// Drives one receipt capture: pick page(s) -> preflight locally -> a Cloud-Function proposal.
/// Pattern lineage is VoiceQuickAddViewModel (capture sheet -> strict parse -> one-shot AppRouter
/// prefill -> user confirms), NOT the oil-analysis in-form coordinator: parsing completes before
/// the entry form exists, so there is no mutation-gating/epoch/quarantine machinery to encode.
@MainActor
@Observable
final class ReceiptCaptureViewModel {
    static let maxPages = ReceiptPreflighter.maxPages

    private let preflighter: any ReceiptPreflighting
    private let service: any ReceiptQuickAddCalling
    private let securityScope: any OilAnalysisPDFSecurityScopeAccessing
    private let analytics: any AnalyticsTracking
    private let now: () -> Date

    private(set) var phase: ReceiptCapturePhase = .idle
    private(set) var imagePages: [ReceiptImagePage] = []
    private(set) var pdfPage: ReceiptPDFPage?
    /// Non-nil once a proposal is ready; the view consumes it exactly once and routes to the form.
    private(set) var proposal: ReceiptEntryProposal?

    private var pdfLease: OilAnalysisPDFSecurityScopeLease?
    private var pdfPreflightTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?

    /// Reentrancy guard (G8, cloned from VoiceQuickAddViewModel.isToggling): the confirm button
    /// stays enabled through the whole `.parsing` round trip. Without this a double-tap re-enters
    /// `confirmAndParse` and calls the metered proposeEntry TWICE for one scan.
    private var isSubmitting = false
    private var quotaFailure: ReceiptCaptureFailure?
    private var notAReceiptBlocked = false

    init(
        preflighter: any ReceiptPreflighting = ReceiptPreflighter(),
        service: any ReceiptQuickAddCalling = ReceiptQuickAddService.shared,
        securityScope: any OilAnalysisPDFSecurityScopeAccessing = URLSecurityScopeAccess(),
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        now: @escaping () -> Date = { .now }
    ) {
        self.preflighter = preflighter
        self.service = service
        self.securityScope = securityScope
        self.analytics = analytics
        self.now = now
    }

    var hasPages: Bool { pdfPage != nil || !imagePages.isEmpty }
    /// A PDF is a whole document (server-side one item); images stack up to `maxPages`. Once
    /// either kind is present the other is locked out — the wire request is images XOR pdfBase64.
    var canAddImage: Bool { pdfPage == nil && imagePages.count < Self.maxPages }
    var canAddPDF: Bool { pdfPage == nil && imagePages.isEmpty }
    var canSubmit: Bool { hasPages && !isSubmitting && quotaFailure == nil && !notAReceiptBlocked }

    func addImage(_ data: Data, source: ReceiptCaptureSource) {
        guard canAddImage else { return }
        reportStartIfFirstPage(source: source)
        if quotaFailure == nil { phase = .preflighting }
        do {
            let preflight = try preflighter.preflightImage(data)
            imagePages.append(ReceiptImagePage(preflight: preflight))
            finishPageMutation()
        } catch let error as ReceiptPreflightError {
            fail(.preflight(error.appError))
        } catch {
            fail(.preflight(.unknown("Couldn't read that photo. Try again.")))
        }
    }

    func addPDF(url: URL) {
        guard canAddPDF else {
            let message = imagePages.isEmpty ? "Only one PDF can be used in a scan."
                : "A PDF and photos cannot be combined in one scan."
            fail(.preflight(.unknown(message)))
            return
        }
        reportStartIfFirstPage(source: .pdf)
        guard let lease = OilAnalysisPDFSecurityScopeLease(url: url, access: securityScope) else {
            fail(.preflight(.unknown("Couldn't access that file.")))
            return
        }
        pdfLease = lease
        if quotaFailure == nil { phase = .preflighting }
        let displayName = url.lastPathComponent
        pdfPreflightTask = Task { [weak self, preflighter] in
            let result = await ReceiptCaptureTaskRunner.preflightPDF(preflighter: preflighter, url: url)
            self?.finishPDFPreflight(result: result, displayName: displayName)
        }
    }

    func removeImagePage(_ id: ReceiptImagePage.ID) {
        guard let index = imagePages.firstIndex(where: { $0.id == id }) else { return }
        imagePages.remove(at: index)
        finishPageMutation()
    }

    func removePDFPage() {
        guard pdfPage != nil else { return }
        pdfLease?.release()
        pdfLease = nil
        pdfPage = nil
        finishPageMutation()
    }

    /// The metered call is owned by a stored Task (mirrors `pdfPreflightTask`) rather than just
    /// running inline, so `abandon()` can cancel it — without this, dismissing the sheet mid-parse
    /// left the callable running with no UI attached, and its (stale) result could still land.
    func confirmAndParse(vehicle: Vehicle?) async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        phase = .parsing
        let images = imagePages.isEmpty ? nil : imagePages.map(\.preflight.parseBase64)
        let pdfBase64 = pdfPage?.base64
        let requestNow = now()
        let task = Task { [weak self, service] in
            let result = await ReceiptCaptureTaskRunner.parse(
                service: service, images: images, pdfBase64: pdfBase64, vehicle: vehicle, now: requestNow
            )
            self?.finishParse(result: result)
        }
        parseTask = task
        await task.value
    }

    /// One-shot handoff: returns the ready proposal plus every kept page's raw bytes, and clears
    /// the proposal so the view routes exactly once.
    func consumeProposalPackage() -> ReceiptPrefillPackage? {
        guard let proposal else { return nil }
        defer { self.proposal = nil }
        return ReceiptPrefillPackage(proposal: proposal, attachments: buildAttachments())
    }

    /// Restores only transient failures without clearing staged pages; retrying a model verdict or
    /// quota denial would spend another unit without creating a more meaningful request.
    func retryAfterFailure() {
        guard case .failed(let failure) = phase, failure.allowsRetry, quotaFailure == nil else { return }
        phase = hasPages ? .ready : .idle
    }

    /// Sheet dismissal mid-flow (mirrors VoiceQuickAddViewModel.abandon): cancels any in-flight
    /// PDF preflight or metered parse call and releases a held security-scope lease, so a
    /// dismissed sheet never leaves background work running — or its stale result landing — with
    /// no UI attached to it.
    func abandon() {
        pdfPreflightTask?.cancel()
        pdfPreflightTask = nil
        parseTask?.cancel()
        parseTask = nil
        pdfLease?.release()
        pdfLease = nil
        phase = .idle
        imagePages = []
        pdfPage = nil
        proposal = nil
        quotaFailure = nil
        notAReceiptBlocked = false
    }

    private func buildAttachments() -> [ReceiptPrefillAttachment] {
        if let pdfPage, let data = Data(base64Encoded: pdfPage.base64) {
            return [ReceiptPrefillAttachment(kind: .pdf, data: data, displayName: pdfPage.displayName)]
        }
        return imagePages.map {
            ReceiptPrefillAttachment(kind: .image, data: $0.preflight.attachmentJPEG, displayName: "Receipt")
        }
    }

    private func reportStartIfFirstPage(source: ReceiptCaptureSource) {
        guard !hasPages else { return }
        analytics.track(.receiptCaptureStarted(source: source))
    }

    /// `Task.isCancelled` here reflects `parseTask` itself (this runs inside its closure) — a
    /// belt-and-braces check beyond catching `CancellationError`, since the underlying callable is
    /// not guaranteed to observe Swift's cooperative cancellation while genuinely in flight. A
    /// cancelled call's result — success OR failure — must never be applied: `abandon()` has
    /// already reset every piece of state this would otherwise touch.
    private func finishParse(result: Result<ReceiptEntryProposal, Error>) {
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let ready):
            proposal = ready
            phase = .ready
            analytics.track(.receiptProposalSucceeded(entryType: ready.entryType))
        case .failure(let error as ReceiptCallableError):
            fail(ReceiptCaptureFailure.map(error))
        case .failure(is CancellationError):
            break
        case .failure(let error):
            fail(.generic(error.localizedDescription))
        }
    }

    private func finishPDFPreflight(result: Result<String, Error>, displayName: String) {
        defer {
            pdfLease?.release()
            pdfLease = nil
        }
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let base64):
            pdfPage = ReceiptPDFPage(base64: base64, displayName: displayName)
            finishPageMutation()
        case .failure(let error as ReceiptPreflightError):
            fail(.preflight(error.appError))
        case .failure(is CancellationError):
            break // abandon() already reset state; nothing more to publish.
        case .failure:
            fail(.preflight(.unknown("Couldn't read that PDF.")))
        }
    }

    /// One funnel keeps quota denials in their richer event family (`receipt_quota_denied`) rather
    /// than folding them into the generic proposal-failure analytics convention.
    private func fail(_ failure: ReceiptCaptureFailure) {
        if failure.isQuotaDenial { quotaFailure = failure }
        if failure == .notAReceipt { notAReceiptBlocked = true }
        phase = .failed(quotaFailure ?? failure)
        if let reason = failure.proposalFailureReason {
            analytics.track(.receiptProposalFailed(reason: reason))
        }
        if let reason = failure.quotaDeniedReason {
            analytics.track(.receiptQuotaDenied(reason: reason))
        }
    }

    /// A changed document clears the model verdict but never clears account quota state: only a
    /// new session can make a quota-blocked scan eligible again.
    private func finishPageMutation() {
        notAReceiptBlocked = false
        phase = quotaFailure.map { .failed($0) } ?? (hasPages ? .ready : .idle)
    }
}
