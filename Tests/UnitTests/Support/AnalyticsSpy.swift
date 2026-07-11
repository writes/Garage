@testable import Garage

@MainActor
final class AnalyticsSpy: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var enabledValues: [Bool] = []
    private var isEnabled = false

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        events.append(event)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        enabledValues.append(enabled)
    }
}
