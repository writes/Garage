import FirebaseFunctions
import Foundation
import Testing
@testable import Garage

struct ClaudeServiceOilAnalysisTests {
    private let now = Date(timeIntervalSince1970: 1_783_944_000) // 2026-07-13T12:00:00.000Z

    @Test func callableClassifier_acceptsOnlyExactFreeLifetimeShape() {
        let error = functionsError(details: [
            "reason": "free_lifetime_exhausted",
            "entitlementUsed": "free"
        ])

        #expect(
            ClaudeService.classifyOilAnalysisQuotaError(error, now: now) == .freeLifetimeExhausted
        )
    }

    @Test func callableClassifier_acceptsOnlyExactProDailyShape() {
        let error = functionsError(details: [
            "reason": "pro_daily_exhausted",
            "entitlementUsed": "pro",
            "resetAt": "2026-07-14T00:00:00.000Z"
        ])

        #expect(
            ClaudeService.classifyOilAnalysisQuotaError(error, now: now) ==
                .proDailyExhausted(resetAt: Date(timeIntervalSince1970: 1_783_987_200))
        )
    }

    @Test func callableClassifier_rejectsWrongFunctionEnvelopeAndMalformedDetails() {
        let exactFree: [String: Any] = [
            "reason": "free_lifetime_exhausted",
            "entitlementUsed": "free"
        ]
        let malformedErrors: [NSError] = [
            functionsError(details: exactFree, domain: "other.domain"),
            functionsError(details: exactFree, code: FunctionsErrorCode.permissionDenied.rawValue),
            functionsError(details: "not a dictionary"),
            NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.resourceExhausted.rawValue),
            functionsError(details: ["entitlementUsed": "free"]),
            functionsError(details: ["reason": 1, "entitlementUsed": "free"]),
            functionsError(details: ["reason": "free_lifetime_exhausted", "entitlementUsed": 1]),
            functionsError(details: ["reason": "unknown", "entitlementUsed": "free"]),
            functionsError(details: ["reason": "free_lifetime_exhausted", "entitlementUsed": "pro"]),
            functionsError(details: [
                "reason": "free_lifetime_exhausted", "entitlementUsed": "free", "resetAt": "unexpected"
            ]),
            functionsError(details: [
                "reason": "pro_daily_exhausted", "entitlementUsed": "pro"
            ]),
            functionsError(details: [
                "reason": "pro_daily_exhausted", "entitlementUsed": "pro", "resetAt": 1_784_084_800
            ]),
            functionsError(details: [
                "reason": "pro_daily_exhausted", "entitlementUsed": "pro",
                "resetAt": "2026-07-13T12:00:00.000Z"
            ]),
            functionsError(details: [
                "reason": "pro_daily_exhausted", "entitlementUsed": "pro",
                "resetAt": "2026-07-14T00:00:00.000Z", "extra": "nope"
            ])
        ]

        for error in malformedErrors {
            #expect(ClaudeService.classifyOilAnalysisQuotaError(error, now: now) == nil)
        }
    }

    @Test func quotaResetParser_requiresExactMillisecondsUtcAndFutureRoundTrip() {
        let accepted = "2026-07-14T00:00:00.000Z"
        let rejected = [
            "2026-07-14T00:00:00Z",
            "2026-07-14T00:00:00.0Z",
            "2026-07-14T00:00:00.0000Z",
            "2026-07-14T00:00:00.000+00:00",
            "2026-07-14T00:00:00.000Ztrailing",
            "2026-02-29T00:00:00.000Z",
            "2026-07-13T12:00:00.000Z",
            "2026-07-13T11:59:59.999Z"
        ]

        #expect(ClaudeService.parseQuotaResetAt(accepted, now: now) != nil)
        for value in rejected {
            #expect(ClaudeService.parseQuotaResetAt(value, now: now) == nil)
        }
    }

    private func functionsError(
        details: Any,
        domain: String = FunctionsErrorDomain,
        code: Int = FunctionsErrorCode.resourceExhausted.rawValue
    ) -> NSError {
        NSError(
            domain: domain,
            code: code,
            userInfo: [FunctionsErrorDetailsKey: details]
        )
    }
}
