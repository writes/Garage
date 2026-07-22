import FirebaseFunctions
import Foundation
import Testing
@testable import Garage

@MainActor
struct VoiceQuickAddServiceTests {
    @Test func decodesProposalFromCallableJSON() throws {
        let json = Data(#"""
        {"entryType":"oil_change","odometerReading":18120,"cost":165,"shopName":null,\#
        "isDiy":true,"entryDate":null,"notes":"Mobil 1 0W-40"}
        """#.utf8)
        let proposal = try JSONDecoder().decode(VoiceEntryProposal.self, from: json)
        #expect(proposal.entryType == .oilChange)
        #expect(proposal.odometerReading == 18120)
        #expect(proposal.cost == 165)
        #expect(proposal.isDiy == true)
        #expect(proposal.entryDate == nil)
        #expect(proposal.notes == "Mobil 1 0W-40")
    }

    @Test func classifiesProRequiredFence() {
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.permissionDenied.rawValue,
            info: ["reason": "pro_required"]
        )
        #expect(VoiceQuickAddService.classifyVoiceError(error, now: .now) == .proRequired)
    }

    @Test func classifiesDailyExhaustedWithFutureReset() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-21T20:00:00Z"))
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.resourceExhausted.rawValue,
            info: ["reason": "voice_daily_exhausted", "resetAt": "2026-07-22T00:00:00.000Z"]
        )
        guard case .dailyExhausted(let resetAt)? = VoiceQuickAddService.classifyVoiceError(error, now: now) else {
            Issue.record("expected dailyExhausted")
            return
        }
        #expect(resetAt > now)
    }

    @Test func ignoresUnrelatedErrors() {
        #expect(VoiceQuickAddService.classifyVoiceError(NSError(domain: "other", code: 1), now: .now) == nil)
    }

    @Test func resolvedDateParsesISOOrFallsBackToDefault() {
        let fallback = Date.now
        let withDate = VoiceEntryProposal(
            entryType: .trackDay, odometerReading: nil, cost: nil, shopName: nil,
            isDiy: nil, entryDate: "2026-07-15T00:00:00.000Z", notes: nil
        )
        #expect(withDate.resolvedDate(default: fallback) != fallback)
        let noDate = VoiceEntryProposal(
            entryType: .fuel, odometerReading: nil, cost: nil, shopName: nil,
            isDiy: nil, entryDate: nil, notes: nil
        )
        #expect(noDate.resolvedDate(default: fallback) == fallback)
    }
}

private extension NSError {
    convenience init(domain: String, code: Int, info: [String: Any]) {
        self.init(domain: domain, code: code, userInfo: [FunctionsErrorDetailsKey: info])
    }
}
