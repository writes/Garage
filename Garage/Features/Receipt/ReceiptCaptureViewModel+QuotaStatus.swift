import Foundation

// Quota-status read/render policy is isolated from capture mutation to keep both files beneath the
// enforced length cap. It has no side effects beyond the optional local status snapshot.

extension ReceiptCaptureViewModel {
    /// PER-ROUTE footer math (spec §21): a save is usable only where BOTH its scan and confirm
    /// capacity exist — `min(base pair) + min(credits pair)`. Summing remainders across routes
    /// would promise saves that cannot be started; the old base-only math undercounted credits.
    var quotaFooterState: ReceiptQuotaFooterState? {
        guard let quotaSnapshot else { return nil }
        let baseUsable = min(quotaSnapshot.confirmedRemaining, quotaSnapshot.scanRemaining)
        let creditsUsable = min(quotaSnapshot.creditsRemaining ?? 0, quotaSnapshot.creditsScanRemaining ?? 0)
        let usable = baseUsable + creditsUsable
        if usable == 0, quotaSnapshot.scanRemaining == 0,
           (quotaSnapshot.creditsScanRemaining ?? 0) == 0 {
            return quotaSnapshot.entitlement == .free ? .freeScansExhausted : .proScansExhausted
        }
        return quotaSnapshot.entitlement == .free
            ? .freeSavesLeft(usable)
            : .proSavesLeft(usable)
    }

    /// The sheet remains usable when this read-only status call fails: only the callable makes an
    /// authoritative admission decision. SwiftUI invokes this when the sheet appears and again
    /// when it reappears after a child presentation. `sweepIncomplete` re-fetches until false
    /// with no cap (each server round strictly consumes expired reservations, so this
    /// converges; capping it stranded paid balances — Sol-final-1); sheet dismissal cancels.
    func refreshQuotaStatus() async {
        do {
            var snapshot = try await service.quotaStatus(transactionID: nil)
            // Uncapped ROUNDS by contract (each server round strictly consumes expired
            // reservations, so this converges — Sol-final-1), but BACKED-OFF delay: a
            // stale/bugged server flag must not draw a steady 2.5 calls/sec from every open
            // sheet (tri-review, all three). Sheet dismissal cancels via the surrounding task.
            var retryDelay: Duration = .milliseconds(400)
            while snapshot.sweepIncomplete == true, !Task.isCancelled {
                try await Task.sleep(for: retryDelay)
                retryDelay = min(retryDelay * 2, .seconds(5))
                snapshot = try await service.quotaStatus(transactionID: nil)
            }
            quotaSnapshot = snapshot
        } catch is CancellationError {
            return
        } catch {
            quotaSnapshot = nil
        }
    }

    /// The one credits→capture coupling: a CONFIRMED grant makes the account admissible again,
    /// so the quota-denial latch clears and the working phase restores — retained pages kept, a
    /// standing `notAReceipt` verdict deliberately NOT cleared (that is document state, and new
    /// credits cannot make the same document a receipt).
    func applyCreditsRecovery(snapshot: ReceiptQuotaSnapshot) {
        quotaSnapshot = snapshot
        guard quotaFailure != nil else { return }
        // The latch clears ONLY when the fresh snapshot shows an actually admissible route —
        // a grant fully absorbed by a refund deficit leaves the account inadmissible, and
        // restoring `.ready` would invite a submit the server must deny (spec §20).
        let baseUsable = min(snapshot.confirmedRemaining, snapshot.scanRemaining)
        let creditsUsable = min(snapshot.creditsRemaining ?? 0, snapshot.creditsScanRemaining ?? 0)
        guard baseUsable + creditsUsable > 0 else { return }
        quotaFailure = nil
        if case .failed = phase {
            phase = notAReceiptBlocked ? .failed(.notAReceipt) : (hasPages ? .ready : .idle)
        }
    }
}
