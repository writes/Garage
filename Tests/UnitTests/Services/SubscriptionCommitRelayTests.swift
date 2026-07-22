import Foundation
import Testing
@testable import Garage

@MainActor
struct SubscriptionCommitRelayTests {
    @Test func prebindDeliveryIsReportedAndDropped() {
        let reporter = SubscriptionReporterSpy()
        let relay = SubscriptionCommitRelay(reporter: reporter)
        relay.deliver(.init(stamp: 7, event: .revokedAll))
        #expect(reporter.violations == [.prebindDelivery(stamp: 7)])
    }

    @Test func secondBindIsRejectedAndFirstSinkRemainsAuthoritative() {
        let reporter = SubscriptionReporterSpy()
        let first = SubscriptionCommitSinkSpy()
        let second = SubscriptionCommitSinkSpy()
        let relay = SubscriptionCommitRelay(reporter: reporter)
        relay.bind(first)
        relay.bind(second)
        relay.deliver(.init(stamp: 1, event: .revokedAll))
        #expect(first.envelopes.count == 1)
        #expect(second.envelopes.isEmpty)
        #expect(reporter.violations == [.secondBind])
    }

    @Test func relayDoesNotRetainItsSink() {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        weak var weakSink: SubscriptionCommitSinkSpy?
        do {
            let sink = SubscriptionCommitSinkSpy()
            weakSink = sink
            relay.bind(sink)
        }
        #expect(weakSink == nil)
        relay.deliver(.init(stamp: 1, event: .revokedAll))
    }

    @Test func exactDuplicateDoesNotMutateOrReportThroughService() {
        let reporter = SubscriptionReporterSpy()
        let service = makeTestService(client: SubscriptionMockClient(), reporter: reporter)
        let envelope = StampedSubscriptionCommit(stamp: 1, event: .revokedAll)
        service.commit(envelope)
        service.commit(envelope)
        #expect(service.accountRevision == 1)
        #expect(reporter.violations.isEmpty)
    }

    @Test func sameStampDifferentPayloadIsReportedAndDropped() {
        let reporter = SubscriptionReporterSpy()
        let service = makeTestService(client: SubscriptionMockClient(), reporter: reporter)
        service.commit(.init(stamp: 1, event: .revokedAll))
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        #expect(reporter.violations == [.sameStampDifferentPayload(stamp: 1)])
        #expect(!service.isPro)
    }

    @Test func staleStampIsReportedWithoutRevokingAcceptedProof() {
        let reporter = SubscriptionReporterSpy()
        let service = makeTestService(client: SubscriptionMockClient(), reporter: reporter)
        service.commit(.init(
            stamp: 2,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        service.commit(.init(stamp: 1, event: .revokedAll))
        #expect(service.isPro)
        #expect(service.accountRevision == 0)
        #expect(reporter.violations == [.staleStamp(received: 1, lastAccepted: 2)])
    }

    @Test func explicitReporterPassthroughPreservesViolation() {
        let reporter = SubscriptionReporterSpy()
        let relay = SubscriptionCommitRelay(reporter: reporter)
        relay.report(.commitLeaseMismatch)
        #expect(reporter.violations == [.commitLeaseMismatch])
    }

    @Test func mismatchCancelsBeforeClearedRevisionIsReported() {
        let trace = PurchaseMutationTrace()
        let scheduler = TracingExpiryScheduler(trace: trace)
        let reporter = TracingSubscriptionReporter(trace: trace)
        let service = makeTestService(
            client: SubscriptionMockClient(), reporter: reporter, scheduler: scheduler
        )
        scheduler.service = service
        reporter.service = service
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        trace.events.removeAll()
        service.commit(.init(
            stamp: 2,
            event: .statusCommitted(lease: SubscriptionFixtures.leaseB, snapshot: SubscriptionFixtures.active)
        ))
        #expect(trace.events == [
            "cancel:revision=0:lease=A:proof=true",
            "report:commitLeaseMismatch:revision=1:cleared=true"
        ])
    }

    @Test func exactCurrentOfferingsBypassWhileCurrentStatusCancels() {
        let trace = PurchaseMutationTrace()
        let scheduler = TracingExpiryScheduler(trace: trace)
        let service = makeTestService(client: SubscriptionMockClient(), scheduler: scheduler)
        scheduler.service = service
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.inactive)
        ))
        trace.events.removeAll()
        service.commit(.init(
            stamp: 2,
            event: .offeringsLoaded(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.plans)
        ))
        service.commit(.init(
            stamp: 3,
            event: .offeringsUnavailable(lease: SubscriptionFixtures.leaseA, retiredEpoch: 2)
        ))
        #expect(trace.events.isEmpty)
        service.commit(.init(
            stamp: 4,
            event: .statusCommitted(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.inactive)
        ))
        #expect(trace.events == ["cancel:revision=0:lease=A:proof=true"])
    }

    @Test func sourcePinsTheOnlyDesignatedInitializerTopology() {
        let source = SubscriptionSourceProbe.read(
            "Garage/Core/Services/Subscription/PurchaseService.swift"
        )
        let eightParameters = """
                clock: any EntitlementClock,
                reporter: any SubscriptionIntegrityReporter,
                analytics: any AnalyticsTracking,
                reconciliationStore: SubscriptionReconciliationStore = SubscriptionReconciliationStore(),
                expirySchedulerFactory: @escaping EntitlementExpirySchedulerFactory,
                clientFactory: @escaping SubscriptionClientFactory,
                gatewayFactory: @escaping SubscriptionGatewayFactory,
                monitorFactory: @escaping SubscriptionMonitorFactory
            ) {
        """
        #expect(!source.contains("constructionToken"))
        #expect(source.contains("#if DEBUG\n    init(\n\(eightParameters)"))
        #expect(source.contains("#else\n    private init(\n\(eightParameters)"))
        #expect(SubscriptionSourceProbe.count("\n    init(\n", in: source) == 1)
        #expect(SubscriptionSourceProbe.count("\n    private init(\n", in: source) == 2)
        #expect(SubscriptionSourceProbe.count("convenience init(", in: source) == 1)
    }
}

@MainActor
private final class PurchaseMutationTrace {
    var events: [String] = []
}

@MainActor
private final class TracingExpiryScheduler: EntitlementExpiryScheduling {
    private let trace: PurchaseMutationTrace
    weak var service: PurchaseService?
    init(trace: PurchaseMutationTrace) { self.trace = trace }
    func start(reevaluator: @escaping @MainActor @Sendable () -> Void) {}
    func replaceWake(after delay: TimeInterval) { trace.events.append("rearm") }
    func cancelWake() {
        let revision = service?.accountRevision ?? .max
        let lease = service?.diagnostics.currentReadyLease?.uid ?? "nil"
        let proof = service?.diagnostics.proofIsPresent == true
        trace.events.append("cancel:revision=\(revision):lease=\(lease):proof=\(proof)")
    }
}

@MainActor
private final class TracingSubscriptionReporter: SubscriptionIntegrityReporter {
    private let trace: PurchaseMutationTrace
    weak var service: PurchaseService?
    init(trace: PurchaseMutationTrace) { self.trace = trace }
    func report(_ violation: SubscriptionIntegrityViolation) {
        let revision = service?.accountRevision ?? .max
        let cleared = service?.diagnostics.currentReadyLease == nil
        trace.events.append("report:\(violation):revision=\(revision):cleared=\(cleared)")
    }
}
