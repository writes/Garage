import Foundation
import Observation

// Phase/failure/page types and the ReceiptCaptureFailure -> analytics-reason mapping live in
// ReceiptCaptureTypes.swift — split out to stay under the file-length cap.

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
    var canAddPage: Bool { pdfPage == nil && imagePages.count < Self.maxPages }

    func addImage(_ data: Data, source: ReceiptCaptureSource) {
        guard canAddPage else { return }
        reportStartIfFirstPage(source: source)
        phase = .preflighting
        do {
            let preflight = try preflighter.preflightImage(data)
            imagePages.append(ReceiptImagePage(preflight: preflight))
            phase = .ready
        } catch let error as ReceiptPreflightError {
            fail(.preflight(error.appError))
        } catch {
            fail(.preflight(.unknown("Couldn't read that photo. Try again.")))
        }
    }

    func addPDF(url: URL) {
        guard pdfPage == nil, imagePages.isEmpty else { return }
        reportStartIfFirstPage(source: .pdf)
        guard let lease = OilAnalysisPDFSecurityScopeLease(url: url, access: securityScope) else {
            fail(.preflight(.unknown("Couldn't access that file.")))
            return
        }
        pdfLease = lease
        phase = .preflighting
        let displayName = url.lastPathComponent
        pdfPreflightTask = Task { [weak self, preflighter] in
            let result = await Self.runPDFPreflight(preflighter: preflighter, url: url)
            self?.finishPDFPreflight(result: result, displayName: displayName)
        }
    }

    func removeImagePage(_ id: ReceiptImagePage.ID) {
        imagePages.removeAll { $0.id == id }
        if !hasPages { phase = .idle }
    }

    func removePDFPage() {
        pdfLease?.release()
        pdfLease = nil
        pdfPage = nil
        phase = .idle
    }

    /// The metered call is owned by a stored Task (mirrors `pdfPreflightTask`) rather than just
    /// running inline, so `abandon()` can cancel it — without this, dismissing the sheet mid-parse
    /// left the callable running with no UI attached, and its (stale) result could still land.
    func confirmAndParse(vehicle: Vehicle?) async {
        guard !isSubmitting, hasPages else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        phase = .parsing
        let images = imagePages.isEmpty ? nil : imagePages.map(\.preflight.parseBase64)
        let pdfBase64 = pdfPage?.base64
        let requestNow = now()
        let task = Task { [weak self, service] in
            let result = await Self.runParse(
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

    /// Recovers from a non-fatal failure WITHOUT clearing any staged page (review finding:
    /// `.failed` used to be a dead end only `abandon()` could exit, silently discarding pages
    /// that had already succeeded). Goes to `.ready` when a page survived, `.idle` otherwise. A
    /// retry of `confirmAndParse` after this is a fresh call, so it re-enters the reentrancy guard
    /// exactly like any other tap.
    func retryAfterFailure() {
        guard case .failed = phase else { return }
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

    private static func runParse(
        service: any ReceiptQuickAddCalling, images: [String]?, pdfBase64: String?, vehicle: Vehicle?, now: Date
    ) async -> Result<ReceiptEntryProposal, Error> {
        do {
            return .success(
                try await service.proposeEntry(images: images, pdfBase64: pdfBase64, vehicle: vehicle, now: now)
            )
        } catch {
            return .failure(error)
        }
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
            fail(Self.map(error))
        case .failure(is CancellationError):
            break
        case .failure(let error):
            fail(.generic(error.localizedDescription))
        }
    }

    private static func runPDFPreflight(
        preflighter: any ReceiptPreflighting, url: URL
    ) async -> Result<String, Error> {
        do {
            return .success(try await preflighter.preflightPDF(url: url))
        } catch {
            return .failure(error)
        }
    }

    private func finishPDFPreflight(result: Result<String, Error>, displayName: String) {
        defer {
            pdfLease?.release()
            pdfLease = nil
        }
        switch result {
        case .success(let base64):
            pdfPage = ReceiptPDFPage(base64: base64, displayName: displayName)
            phase = .ready
        case .failure(let error as ReceiptPreflightError):
            fail(.preflight(error.appError))
        case .failure(is CancellationError):
            break // abandon() already reset state; nothing more to publish.
        case .failure:
            fail(.preflight(.unknown("Couldn't read that PDF.")))
        }
    }

    /// Single funnel exit for non-quota endings: quota denials keep their own richer event
    /// (`receipt_quota_denied`, the oil-analysis convention) rather than folding into this one.
    private func fail(_ failure: ReceiptCaptureFailure) {
        phase = .failed(failure)
        if let reason = failure.proposalFailureReason {
            analytics.track(.receiptProposalFailed(reason: reason))
        }
        if let reason = failure.quotaDeniedReason {
            analytics.track(.receiptQuotaDenied(reason: reason))
        }
    }

    private static func map(_ error: ReceiptCallableError) -> ReceiptCaptureFailure {
        switch error {
        case .notAReceipt: return .notAReceipt
        case .freeLifetimeExhausted: return .freeLifetimeExhausted
        case .dailyExhausted(let resetAt): return .dailyExhausted(resetAt: resetAt)
        }
    }
}
