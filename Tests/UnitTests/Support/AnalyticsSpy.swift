import RevenueCat
@testable import Garage

@MainActor
final class AnalyticsSpy: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var enabledValues: [Bool] = []
    private var isEnabled = false
    private var isCollectionSuppressedForCurrentSession = false

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        events.append(event)
    }

    func setEnabled(_ enabled: Bool) {
        let effectiveEnabled = enabled && !isCollectionSuppressedForCurrentSession
        isEnabled = effectiveEnabled
        enabledValues.append(effectiveEnabled)
    }

    func suppressCollectionForCurrentSession() {
        isCollectionSuppressedForCurrentSession = true
        setEnabled(false)
    }
}

@MainActor
final class PurchaseResultProbe {
    private let result: PurchaseResultData
    private(set) var calls = 0

    init(result: PurchaseResultData) {
        self.result = result
    }

    func load() async throws -> PurchaseResultData {
        calls += 1
        return result
    }
}
