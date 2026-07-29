import FirebaseFunctions
import Foundation
import Testing
@testable import Garage

@MainActor
struct ReceiptQuickAddServiceTests {
    @Test func decodesProposalFromCallableJSON() throws {
        let json = Data(#"""
        {"entryType":"oil_change","odometerReading":18120,"cost":165,"shopName":"Joe's Garage",\#
        "isDiy":false,"entryDate":null,"notes":"Synthetic blend","lineItems":["Oil filter — $12.00"]}
        """#.utf8)
        let proposal = try JSONDecoder().decode(ReceiptEntryProposal.self, from: json)
        #expect(proposal.entryType == .oilChange)
        #expect(proposal.odometerReading == 18120)
        #expect(proposal.cost == 165)
        #expect(proposal.shopName == "Joe's Garage")
        #expect(proposal.isDiy == false)
        #expect(proposal.notes == "Synthetic blend")
        #expect(proposal.lineItems == ["Oil filter — $12.00"])
    }

    @Test func classifiesNotAReceipt() {
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            info: ["reason": "not_a_receipt"]
        )
        #expect(ReceiptQuickAddService.classifyReceiptError(error, now: .now) == .notAReceipt)
    }

    @Test func classifiesFreeLifetimeExhausted() {
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.resourceExhausted.rawValue,
            info: ["reason": "receipt_free_exhausted"]
        )
        #expect(ReceiptQuickAddService.classifyReceiptError(error, now: .now) == .freeLifetimeExhausted)
    }

    @Test func classifiesDailyExhaustedWithFutureReset() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-28T20:00:00Z"))
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.resourceExhausted.rawValue,
            info: ["reason": "receipt_daily_exhausted", "resetAt": "2026-07-29T00:00:00.000Z"]
        )
        guard case .dailyExhausted(let resetAt)? = ReceiptQuickAddService.classifyReceiptError(error, now: now) else {
            Issue.record("expected dailyExhausted")
            return
        }
        #expect(resetAt > now)
    }

    /// Only the three documented shapes may affect product routing — this model has no
    /// `permission-denied pro_required` path (F4), so it must fall through like anything else.
    @Test func ignoresUnrelatedAndVestigialErrors() {
        #expect(ReceiptQuickAddService.classifyReceiptError(NSError(domain: "other", code: 1), now: .now) == nil)
        let proRequired = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.permissionDenied.rawValue,
            info: ["reason": "pro_required"]
        )
        #expect(ReceiptQuickAddService.classifyReceiptError(proRequired, now: .now) == nil)
    }

    @Test func resolvedDateParsesISOOrFallsBackToDefault() {
        let fallback = Date.now
        let withDate = ReceiptEntryProposal(
            entryType: .tire, odometerReading: nil, cost: nil, shopName: nil,
            isDiy: nil, entryDate: "2026-07-15T00:00:00.000Z", notes: nil, lineItems: nil
        )
        #expect(withDate.resolvedDate(default: fallback) != fallback)
        let noDate = ReceiptEntryProposal(
            entryType: .fuel, odometerReading: nil, cost: nil, shopName: nil,
            isDiy: nil, entryDate: nil, notes: nil, lineItems: nil
        )
        #expect(noDate.resolvedDate(default: fallback) == fallback)
    }
}

private extension NSError {
    convenience init(domain: String, code: Int, info: [String: Any]) {
        self.init(domain: domain, code: code, userInfo: [FunctionsErrorDetailsKey: info])
    }
}
