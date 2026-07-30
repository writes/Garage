import Foundation
import Testing
@testable import Garage

/// The one parse both quick-add proposals now share. The per-type tests still pin that voice and
/// receipt proposals route through it; these pin what it actually accepts — in particular the
/// no-fractional-seconds form, which neither copy of the duplicated implementation ever tested.
struct QuickAddProposalDateTests {
    @Test func parsesTheServersFractionalSecondsForm() throws {
        let parsed = QuickAddProposalDate.resolve("2026-07-15T00:00:00.000Z", default: .distantPast)
        var components = DateComponents()
        components.year = 2_026
        components.month = 7
        components.day = 15
        components.timeZone = TimeZone(identifier: "UTC")
        let expected = try #require(Calendar(identifier: .gregorian).date(from: components))
        #expect(abs(parsed.timeIntervalSince(expected)) < 1)
    }

    @Test func parsesAnEchoedDateWithoutFractionalSeconds() {
        // A value round-tripped by anything that drops milliseconds must still parse; falling back
        // would silently relabel the owner's receipt as today.
        #expect(QuickAddProposalDate.resolve("2026-07-15T00:00:00Z", default: .distantPast) != .distantPast)
    }

    @Test func fallsBackForNilAndForUnparseableText() {
        let fallback = Date(timeIntervalSince1970: 1_000)
        #expect(QuickAddProposalDate.resolve(nil, default: fallback) == fallback)
        #expect(QuickAddProposalDate.resolve("last Tuesday", default: fallback) == fallback)
    }
}
