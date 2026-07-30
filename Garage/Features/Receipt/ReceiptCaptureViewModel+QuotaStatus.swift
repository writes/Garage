import Foundation

// Quota-status read/render policy is isolated from capture mutation to keep both files beneath the
// enforced length cap. It has no side effects beyond the optional local status snapshot.

extension ReceiptCaptureViewModel {
    var quotaFooterState: ReceiptQuotaFooterState? {
        guard let quotaSnapshot else { return nil }
        if quotaSnapshot.scanRemaining == 0 {
            return quotaSnapshot.entitlement == .free ? .freeScansExhausted : .proScansExhausted
        }
        return quotaSnapshot.entitlement == .free
            ? .freeSavesLeft(quotaSnapshot.confirmedRemaining)
            : .proSavesLeft(quotaSnapshot.confirmedRemaining)
    }

    /// The sheet remains usable when this read-only status call fails: only the callable makes an
    /// authoritative admission decision. SwiftUI invokes this when the sheet appears and again
    /// when it reappears after a child presentation.
    func refreshQuotaStatus() async {
        do {
            quotaSnapshot = try await service.quotaStatus()
        } catch is CancellationError {
            return
        } catch {
            quotaSnapshot = nil
        }
    }
}
