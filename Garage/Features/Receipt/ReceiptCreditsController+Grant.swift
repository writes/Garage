import Foundation

// The purchase→grant resolution machinery, split from ReceiptCreditsController.swift for the
// file-length cap. Everything here runs on the controller's identity LEASE: the uid captured
// when the flow started, re-checked after every await (tri-review Sol blocker).

extension ReceiptCreditsController {
    /// What the one post-TTL attempt concluded (tri-review r2, both dissenters): only a
    /// DEFINITIVE miss — a reconcile that ran under the right account and authoritatively
    /// found nothing — may destroy the repair key. A thrown auth/network/429/5xx or a lease
    /// mismatch is indeterminate: the marker survives and retries on the next appear.
    private enum TTLOutcome {
        case resolved
        case definitiveMiss
        case indeterminate
    }

    /// Resumes every outstanding marker for the signed-in uid (sheet appear). An expired
    /// marker gets a final status/reconcile before being declared lost — TTL must not orphan
    /// a grant that landed while the app was closed (tri-review Sol blocker).
    func resumeOutstandingMarkers(recoveringInto viewModel: ReceiptCaptureViewModel) async {
        guard let uid = currentUID() else { return }
        let (active, expired) = markers.unexpiredMarkers(uid: uid, now: now())
        var anyUnresolved = false
        for marker in expired {
            switch await finalReconcile(
                transactionID: marker.transactionID, expectedUID: uid, viewModel: viewModel
            ) {
            case .resolved:
                continue
            case .definitiveMiss:
                // The server authoritatively never saw this payment, so the purchase never
                // credited: a fresh Buy is a NEW need, not a double charge, and the durable
                // support notice covers the money trail (tri-review r2 disposition).
                markers.markExpiredUnresolved(transactionID: marker.transactionID, uid: uid)
                analytics.track(.receiptCreditsGrantMissing)
            case .indeterminate:
                anyUnresolved = true
            }
        }
        for marker in active {
            let terminal = await pollOnce(
                transactionID: marker.transactionID, expectedUID: uid,
                viewModel: viewModel, thenReconcile: true
            )
            if !terminal { anyUnresolved = true }
        }
        // An unresolved paid purchase suppresses Buy (only `.idle` renders it): re-offering
        // while a grant is pending invites a second charge (tri-review Sol blocker).
        if anyUnresolved, purchaseState == .idle { purchaseState = .delayed }
    }

    /// Called only by `purchase(recoveringInto:)` — internal solely for the file split.
    func awaitGrant(transactionID: String, viewModel: ReceiptCaptureViewModel) async {
        purchaseState = .waitingForGrant
        // The identity LEASE: every later apply re-checks against this uid — an account switch
        // mid-poll must not push another account's quota into this sheet or resolve the marker
        // under the wrong owner (tri-review Sol blocker).
        guard let uid = currentUID() else {
            purchaseState = .delayed
            analytics.track(.receiptCreditsGrantDelayed)
            return
        }
        guard !transactionID.isEmpty else {
            await recoverWithoutTransactionID(leaseUID: uid, viewModel: viewModel)
            return
        }
        for delay in Self.pollDelays {
            if (try? await sleeper(delay)) == nil {
                // Sheet dismissed mid-poll: the marker persists and resumes on next appear.
                purchaseState = .delayed
                return
            }
            guard currentUID() == uid else {
                // User changed mid-poll: stop — the marker resumes on the paying account.
                purchaseState = .delayed
                return
            }
            if await pollOnce(
                transactionID: transactionID, expectedUID: uid,
                viewModel: viewModel, thenReconcile: false
            ) { return }
        }
        analytics.track(.receiptCreditsGrantDelayed)
        if await pollOnce(
            transactionID: transactionID, expectedUID: uid, viewModel: viewModel,
            thenReconcile: true, reportMissOnReconcileFailure: true
        ) { return }
        purchaseState = .delayed
    }

    /// No SDK transaction id → nothing to poll or reconcile; the balance-bearing refresh is the
    /// only signal. A landed grant must route through the ONE recovery hook so the latch clears
    /// NOW, not on the next sheet open (tri-review Sol blocker). The purchaser only reaches
    /// this path with identity held at completion (tri-review r2).
    private func recoverWithoutTransactionID(
        leaseUID: String, viewModel: ReceiptCaptureViewModel
    ) async {
        await viewModel.refreshQuotaStatus()
        if let snapshot = viewModel.quotaSnapshot, currentUID() == leaseUID {
            viewModel.applyCreditsRecovery(snapshot: snapshot)
        }
        if viewModel.quotaFailure == nil {
            // Admissible again — the credits demonstrably arrived. No grant_confirmed here:
            // that metric requires a transaction-terminal `granted`, unobservable on this path.
            purchaseState = .granted
        } else {
            purchaseState = .delayed
            analytics.track(.receiptCreditsGrantDelayed)
        }
    }

    /// The one post-TTL attempt: status first, then a reconcile whose thrown ERROR is
    /// distinguished from its empty success — `try?` here turned transient failures into
    /// permanent repair-key destruction (tri-review r2, both dissenters).
    private func finalReconcile(
        transactionID: String, expectedUID: String, viewModel: ReceiptCaptureViewModel
    ) async -> TTLOutcome {
        if let snapshot = try? await service.quotaStatus(transactionID: transactionID),
           applyTerminal(
               snapshot: snapshot, transactionID: transactionID,
               expectedUID: expectedUID, viewModel: viewModel
           ) {
            return .resolved
        }
        do {
            let snapshot = try await service.reconcileCreditPurchase(transactionID: transactionID)
            if applyTerminal(
                snapshot: snapshot, transactionID: transactionID,
                expectedUID: expectedUID, viewModel: viewModel
            ) {
                return .resolved
            }
            // A reconcile that ran under another account's auth is not authoritative for the
            // paying uid (the lease mismatch inside applyTerminal also lands here).
            return currentUID() == expectedUID ? .definitiveMiss : .indeterminate
        } catch {
            return .indeterminate
        }
    }

    /// One status/reconcile round. Returns true when a TERMINAL state was reached.
    /// `grant_missing` fires ONLY from the post-purchase window's final reconcile miss (and
    /// marker expiry) — emitting it on every sheet-appear resume would spam the ops metric for
    /// transactions that are merely still in flight (Gemini client-check #2).
    @discardableResult
    private func pollOnce(
        transactionID: String, expectedUID: String, viewModel: ReceiptCaptureViewModel,
        thenReconcile: Bool, reportMissOnReconcileFailure: Bool = false
    ) async -> Bool {
        if let snapshot = try? await service.quotaStatus(transactionID: transactionID),
           applyTerminal(
               snapshot: snapshot, transactionID: transactionID,
               expectedUID: expectedUID, viewModel: viewModel
           ) {
            return true
        }
        guard thenReconcile else { return false }
        // Only a reconcile that SUCCEEDED and still found nothing is a real miss — thrown
        // auth/network/429/5xx errors are retryable, never lost-webhook signals (tri-review).
        if let snapshot = try? await service.reconcileCreditPurchase(transactionID: transactionID) {
            if applyTerminal(
                snapshot: snapshot, transactionID: transactionID,
                expectedUID: expectedUID, viewModel: viewModel
            ) {
                return true
            }
            if reportMissOnReconcileFailure {
                analytics.track(.receiptCreditsGrantMissing)
            }
        }
        return false
    }

    /// Routes BOTH polling and reconcile through one terminal transition (Sol-r3-9).
    private func applyTerminal(
        snapshot: ReceiptQuotaSnapshot, transactionID: String, expectedUID: String,
        viewModel: ReceiptCaptureViewModel
    ) -> Bool {
        // The snapshot was fetched under whoever is CURRENTLY signed in; on lease mismatch it
        // belongs to another account. Not terminal — the marker stays for the right account's
        // next resume (tri-review Sol blocker).
        guard currentUID() == expectedUID else { return false }
        switch snapshot.transactionState {
        case .granted:
            markers.resolve(transactionID: transactionID, uid: expectedUID)
            analytics.track(.receiptCreditsGrantConfirmed)
            viewModel.applyCreditsRecovery(snapshot: snapshot)
            // A grant fully absorbed by a refund deficit leaves the account inadmissible: the
            // latch stays, so the UI must NOT celebrate or hide the buy affordance (spec §19
            // keeps the purchase available; tri-review codex finding).
            purchaseState = viewModel.quotaFailure == nil ? .granted : .idle
            return true
        case .refunded:
            markers.resolve(transactionID: transactionID, uid: expectedUID)
            analytics.track(.receiptCreditsRefundObserved)
            purchaseState = .refunded
            // Fresh server numbers still apply (deficit/balance changed) — only the latch
            // stays: a refund never restores admissibility (Gemini client-check #3).
            viewModel.quotaSnapshot = snapshot
            return true
        case .unknown, nil:
            return false
        }
    }
}
