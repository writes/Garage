import Foundation
import Testing
@testable import Garage

@MainActor
struct NotificationFunnelServiceTests {
    private final class AnalyticsSpy: AnalyticsTracking {
        var events: [AnalyticsEvent] = []
        func track(_ event: AnalyticsEvent) { events.append(event) }
        func setEnabled(_: Bool) {}
    }

    private func makeService(spy: AnalyticsSpy) -> NotificationFunnelService {
        NotificationFunnelService(defaults: nil, analytics: spy)
    }

    @Test func openThenCompletionInsideTheWindowAttributes() {
        let spy = AnalyticsSpy()
        let service = makeService(spy: spy)
        let opened = Date(timeIntervalSince1970: 1_000_000)
        service.recordOpen(.reminderDue, now: opened)
        service.recordTaskCompletionIfAttributed(.reminderDue, now: opened.addingTimeInterval(3 * 24 * 3600))
        #expect(spy.events == [
            .notifOpened(category: .reminderDue),
            .notifTaskCompleted(category: .reminderDue)
        ])
    }

    @Test func completionOutsideTheWindowDoesNotAttribute() {
        let spy = AnalyticsSpy()
        let service = makeService(spy: spy)
        let opened = Date(timeIntervalSince1970: 1_000_000)
        service.recordOpen(.reminderDue, now: opened)
        service.recordTaskCompletionIfAttributed(
            .reminderDue,
            now: opened.addingTimeInterval(NotificationFunnelService.attributionWindow + 1)
        )
        #expect(spy.events == [.notifOpened(category: .reminderDue)])
    }

    @Test func oneOpenAttributesAtMostOneCompletion() {
        let spy = AnalyticsSpy()
        let service = makeService(spy: spy)
        let opened = Date(timeIntervalSince1970: 1_000_000)
        service.recordOpen(.reminderDue, now: opened)
        service.recordTaskCompletionIfAttributed(.reminderDue, now: opened.addingTimeInterval(60))
        service.recordTaskCompletionIfAttributed(.reminderDue, now: opened.addingTimeInterval(120))
        #expect(spy.events.filter { $0 == .notifTaskCompleted(category: .reminderDue) }.count == 1)
    }

    @Test func completionWithoutAnyOpenIsANoOp() {
        let spy = AnalyticsSpy()
        makeService(spy: spy).recordTaskCompletionIfAttributed(.reminderDue)
        #expect(spy.events.isEmpty)
    }

    @Test func scheduledEmitsTheFunnelEntry() {
        let spy = AnalyticsSpy()
        makeService(spy: spy).recordScheduled(.reminderDue)
        #expect(spy.events == [.notifScheduled(category: .reminderDue)])
    }
}
