import Foundation
import Testing
@testable import Garage
enum SubscriptionFixtures {
    static let leaseA = IdentityLease(uid: "A", generation: 1)
    static let leaseB = IdentityLease(uid: "B", generation: 2)
    static let active = EntitlementSnapshot(
        isActive: true,
        expirationDate: nil,
        productID: Constants.monthlyPlanIdentifier
    )
    static let inactive = EntitlementSnapshot(
        isActive: false,
        expirationDate: nil,
        productID: nil
    )
    static let package = PackageDTO(
        handle: PackageHandle(cacheEpoch: 1, ordinal: 1),
        offeringID: "default",
        packageID: "$rc_monthly",
        productID: Constants.monthlyPlanIdentifier,
        analyticsProduct: .monthly,
        title: "Monthly",
        packageDescription: "Garage Pro monthly",
        localizedPrice: "$4.99",
        period: SubscriptionPeriodDTO(value: 1, unit: .month)
    )
    static let plans = OfferingsSnapshot(
        epoch: 1,
        offeringID: "default",
        packages: [package],
        omittedUnknownProductIDs: []
    )
    static let selection = PackageSelection(
        lease: leaseA,
        handle: package.handle,
        offeringID: package.offeringID,
        packageID: package.packageID,
        productID: package.productID,
        analyticsProduct: package.analyticsProduct
    )
}
@MainActor
final class AdjustableEntitlementClock: EntitlementClock {
    var value: Date
    private(set) var reads = 0
    init(_ value: Date = Date(timeIntervalSince1970: 1_000)) { self.value = value }
    func now() -> Date {
        reads += 1
        return value
    }
}
@MainActor
final class SubscriptionReporterSpy: SubscriptionIntegrityReporter {
    private(set) var violations: [SubscriptionIntegrityViolation] = []
    func report(_ violation: SubscriptionIntegrityViolation) { violations.append(violation) }
}
@MainActor
final class SubscriptionCommitSinkSpy: SubscriptionCommitSink {
    private(set) var envelopes: [StampedSubscriptionCommit] = []
    func commit(_ envelope: StampedSubscriptionCommit) { envelopes.append(envelope) }
}
@MainActor
final class SubscriptionCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
@MainActor
final class SubscriptionStringBox {
    var value: String
    init(_ value: String) { self.value = value }
}
@MainActor
final class ManualExpiryScheduler: EntitlementExpiryScheduling {
    private(set) var starts = 0
    private(set) var replacements: [TimeInterval] = []
    private(set) var cancellations = 0
    private var reevaluator: (@MainActor @Sendable () -> Void)?
    func start(reevaluator: @escaping @MainActor @Sendable () -> Void) {
        starts += 1
        self.reevaluator = reevaluator
    }
    func replaceWake(after delay: TimeInterval) { replacements.append(delay) }
    func cancelWake() { cancellations += 1 }
    func fire() { reevaluator?() }
}
@MainActor
final class ScriptedSubscriptionFacade: SubscriptionFacading {
    var isPro = false
    var plans: OfferingsSnapshot?
    var accountRevision: UInt64 = 0
    var pendingReconciliation: SubscriptionReconciliationKind?
    var status: [StatusOutcome] = []
    var offerings: [OfferingsOutcome] = []
    var purchases: [PurchaseOutcome] = []
    var restores: [RestoreOutcome] = []
    var selection: PackageSelection?
    var onStatus: (() -> Void)?
    var onPurchase: (() -> Void)?
    var onRestore: (() -> Void)?
    private(set) var statusCalls = 0
    private(set) var offeringsCalls = 0
    private(set) var selectionCalls = 0
    private(set) var purchaseCalls = 0
    private(set) var restoreCalls = 0
    func makeSelection(for dto: PackageDTO) -> PackageSelection? {
        selectionCalls += 1
        return pendingReconciliation == nil ? selection : nil
    }
    func refreshStatus() async -> StatusOutcome {
        statusCalls += 1
        onStatus?()
        return status.isEmpty ? .notReady : status.removeFirst()
    }
    func loadOfferings() async -> OfferingsOutcome {
        offeringsCalls += 1
        return offerings.isEmpty ? .notReady : offerings.removeFirst()
    }
    func purchase(_ selection: PackageSelection) async -> PurchaseOutcome {
        purchaseCalls += 1
        onPurchase?()
        let outcome = purchases.isEmpty ? .notReady : purchases.removeFirst()
        if outcome == .reconciliationRequired { pendingReconciliation = .purchase }
        return outcome
    }
    func restore() async -> RestoreOutcome {
        restoreCalls += 1
        onRestore?()
        let outcome = restores.isEmpty ? .notReady : restores.removeFirst()
        if outcome == .reconciliationRequired, pendingReconciliation == nil {
            pendingReconciliation = .restore
        } else if outcome == .activeEntitlement ||
                    (outcome == .noActiveEntitlement && pendingReconciliation == .restore) {
            pendingReconciliation = nil
        }
        return outcome
    }
}
@MainActor
func makeTestService(
    client: SubscriptionMockClient,
    clock: AdjustableEntitlementClock = AdjustableEntitlementClock(),
    reporter: any SubscriptionIntegrityReporter = SubscriptionReporterSpy(),
    analytics: AnalyticsSpy = AnalyticsSpy(),
    reconciliationStore: SubscriptionReconciliationStore = SubscriptionReconciliationStore(),
    scheduler: any EntitlementExpiryScheduling = ManualExpiryScheduler()
) -> PurchaseService {
    PurchaseService(
        clock: clock,
        reporter: reporter,
        analytics: analytics,
        reconciliationStore: reconciliationStore,
        expirySchedulerFactory: { scheduler },
        clientFactory: { client },
        gatewayFactory: { SubscriptionGateway(client: $0, relay: $1) },
        monitorFactory: { retry in
            SubscriptionRecoveryMonitor(
                pathSource: TestNetworkSource(),
                foregroundSource: TestForegroundSource(),
                retry: retry
            )
        }
    )
}
@MainActor
final class TestNetworkSource: NetworkPathEventSource {
    private(set) var handlers: [@Sendable (NetworkPathVerdict) -> Void] = []
    func subscribe(
        _ handler: @escaping @Sendable (NetworkPathVerdict) -> Void
    ) -> RecoverySubscriptionToken {
        handlers.append(handler)
        return RecoverySubscriptionToken {}
    }
}
@MainActor
final class TestForegroundSource: ForegroundEventSource {
    private(set) var handlers: [@Sendable () -> Void] = []
    func subscribe(_ handler: @escaping @Sendable () -> Void) -> RecoverySubscriptionToken {
        handlers.append(handler)
        return RecoverySubscriptionToken {}
    }
}
enum SubscriptionSourceProbe {
    static func read(_ relativePath: String, from file: StaticString = #filePath) -> String {
        let fileURL = URL(fileURLWithPath: String(describing: file))
        let root = fileURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)) ?? ""
    }

    static func count(_ needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    static func containsInOrder(_ fragments: [String], in source: String) -> Bool {
        var remainder = source[...]
        for fragment in fragments {
            guard let range = remainder.range(of: fragment) else { return false }
            remainder = remainder[range.upperBound...]
        }
        return true
    }
}
@MainActor
final class EntryPageFetchProbe {
    private var continuations: [CheckedContinuation<EntryPage, Never>] = []
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var calls = 0
    private(set) var queries: [EntryQuery] = []
    func load(_ query: EntryQuery, _ limit: Int, _ cursor: EntryCursor?) async throws -> EntryPage {
        calls += 1
        queries.append(query)
        let ready = callWaiters.filter { $0.0 <= calls }
        callWaiters.removeAll { $0.0 <= calls }
        ready.forEach { $0.1.resume() }
        return await withCheckedContinuation { continuations.append($0) }
    }
    func waitUntilCalled(_ count: Int = 1) async {
        if calls >= count { return }
        await withCheckedContinuation { callWaiters.append((count, $0)) }
    }
    func resolve(_ entries: [FirestoreEntry]) { resolveNext(EntryPage(entries: entries, nextCursor: nil)) }
    func resolveNext(_ page: EntryPage) { continuations.removeFirst().resume(returning: page) }
}
@MainActor
final class CSVURLSequence {
    private var urls: [URL]
    private(set) var calls = 0
    init(_ urls: [URL]) { self.urls = urls }
    func next() -> URL {
        calls += 1
        return urls.removeFirst()
    }
}
