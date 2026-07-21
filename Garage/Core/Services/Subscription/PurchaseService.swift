import Foundation
import Observation
@MainActor
@Observable
final class PurchaseService: SubscriptionCommitSink, SubscriptionFacading {
    static let shared = PurchaseService(
        clock: SystemEntitlementClock(),
        reporter: LoggingSubscriptionIntegrityReporter(),
        analytics: AnalyticsService.shared,
        reconciliationStore: SubscriptionReconciliationStore(defaults: .standard),
        expirySchedulerFactory: { EntitlementExpiryScheduler() },
        clientFactory: { LiveRevenueCatClient() },
        gatewayFactory: { SubscriptionGateway(client: $0, relay: $1) },
        monitorFactory: { retry in
            SubscriptionRecoveryMonitor(
                pathSource: LiveNetworkPathEventSource(),
                foregroundSource: LiveForegroundEventSource(),
                retry: retry
            )
        }
    )
    static let uiTest = PurchaseService(
        inertIsPro: AppRuntime.isUITestPro,
        analytics: NoopAnalyticsService(),
        reporter: LoggingSubscriptionIntegrityReporter(),
        expiryScheduler: EntitlementExpiryScheduler()
    )

    private let relay: SubscriptionCommitRelay
    private let gateway: SubscriptionGateway?
    private let monitor: SubscriptionRecoveryMonitor?
    private let expiryScheduler: any EntitlementExpiryScheduling
    private let clock: any EntitlementClock
    private let analytics: any AnalyticsTracking
    private let reconciliationStore: SubscriptionReconciliationStore
    private var state = PurchaseServiceState()

    var isPro: Bool { state.isPro { clock.now() } }
    var plans: OfferingsSnapshot? { state.plans }
    var accountRevision: UInt64 { state.accountRevision }
    var pendingReconciliation: SubscriptionReconciliationKind? { reconciliationStore.kind }
    #if DEBUG
    init(
        clock: any EntitlementClock,
        reporter: any SubscriptionIntegrityReporter,
        analytics: any AnalyticsTracking,
        reconciliationStore: SubscriptionReconciliationStore = SubscriptionReconciliationStore(),
        expirySchedulerFactory: @escaping EntitlementExpirySchedulerFactory,
        clientFactory: @escaping SubscriptionClientFactory,
        gatewayFactory: @escaping SubscriptionGatewayFactory,
        monitorFactory: @escaping SubscriptionMonitorFactory
    ) {
        let components = SubscriptionRuntimeFactory.make(
            reporter: reporter, expirySchedulerFactory: expirySchedulerFactory,
            clientFactory: clientFactory, gatewayFactory: gatewayFactory,
            monitorFactory: monitorFactory
        )
        relay = components.relay
        gateway = components.gateway
        monitor = components.monitor
        expiryScheduler = components.scheduler
        self.clock = clock
        self.analytics = analytics
        self.reconciliationStore = reconciliationStore
        relay.bind(self)
        expiryScheduler.start { [weak self] in self?.reevaluateEntitlementExpiry() }
        monitor?.start()
    }
    #else
    private init(
        clock: any EntitlementClock,
        reporter: any SubscriptionIntegrityReporter,
        analytics: any AnalyticsTracking,
        reconciliationStore: SubscriptionReconciliationStore = SubscriptionReconciliationStore(),
        expirySchedulerFactory: @escaping EntitlementExpirySchedulerFactory,
        clientFactory: @escaping SubscriptionClientFactory,
        gatewayFactory: @escaping SubscriptionGatewayFactory,
        monitorFactory: @escaping SubscriptionMonitorFactory
    ) {
        let components = SubscriptionRuntimeFactory.make(
            reporter: reporter, expirySchedulerFactory: expirySchedulerFactory,
            clientFactory: clientFactory, gatewayFactory: gatewayFactory,
            monitorFactory: monitorFactory
        )
        relay = components.relay
        gateway = components.gateway
        monitor = components.monitor
        expiryScheduler = components.scheduler
        self.clock = clock
        self.analytics = analytics
        self.reconciliationStore = reconciliationStore
        relay.bind(self)
        expiryScheduler.start { [weak self] in self?.reevaluateEntitlementExpiry() }
        monitor?.start()
    }
    #endif

    private init(
        inertIsPro: Bool,
        analytics: any AnalyticsTracking,
        reporter: any SubscriptionIntegrityReporter,
        expiryScheduler: any EntitlementExpiryScheduling
    ) {
        let relay = SubscriptionCommitRelay(reporter: reporter)
        self.relay = relay
        gateway = nil
        monitor = nil
        self.expiryScheduler = expiryScheduler
        clock = SystemEntitlementClock()
        self.analytics = analytics
        reconciliationStore = SubscriptionReconciliationStore()
        if inertIsPro {
            let lease = IdentityLease(uid: "inert", generation: 1)
            state.currentReadyLease = lease
            state.proof = EntitlementProof(isActive: true, expirationDate: nil, lease: lease)
        }
        relay.bind(self)
    }

    #if DEBUG
    convenience init(
        testIsPro: Bool,
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.init(
            inertIsPro: testIsPro,
            analytics: analytics,
            reporter: LoggingSubscriptionIntegrityReporter(),
            expiryScheduler: EntitlementExpiryScheduler()
        )
    }
    #endif

    @discardableResult
    func setDesiredFirebaseUID(_ uid: String?) -> OperationTicket<IdentityOutcome>? {
        gateway?.setDesiredFirebaseUID(uid)
    }

    func makeSelection(for dto: PackageDTO) -> PackageSelection? {
        guard pendingReconciliation == nil else { state.storedSelection = nil; return nil }
        return state.makeSelection(for: dto, enabled: gateway != nil)
    }

    func checkSubscriptionStatus() async {
        guard let ticket = gateway?.registerStatus() else { return }
        _ = await ticket.awaitValue()
    }

    func refreshStatus() async -> StatusOutcome {
        guard let ticket = gateway?.registerStatus() else { return .notReady }
        return await ticket.awaitValue()
    }

    func loadOfferings() async -> OfferingsOutcome {
        guard let ticket = gateway?.registerOfferings() else { return .notReady }
        return await ticket.awaitValue()
    }

    func purchase(_ selection: PackageSelection) async -> PurchaseOutcome {
        guard pendingReconciliation == nil else {
            state.storedSelection = nil
            return .reconciliationRequired
        }
        guard selection == state.storedSelection, let gateway else {
            state.storedSelection = nil
            return .selectionInvalidated
        }
        let outcome = await gateway.registerPurchase(selection).awaitValue()
        if outcome != .busy { state.storedSelection = nil }
        let resolved = outcome == .activePro && !isPro ? .noEntitlement : outcome
        reconciliationStore.observePurchase(resolved, uid: selection.lease.uid)
        return resolved
    }

    func restore() async -> RestoreOutcome {
        guard let gateway else { return .notReady }
        let originUID = state.currentReadyLease?.uid
        let outcome = await gateway.registerRestore().awaitValue()
        let resolved = outcome == .activeEntitlement && !isPro ? .noActiveEntitlement : outcome
        reconciliationStore.observeRestore(resolved, uid: originUID)
        return resolved
    }

    func requestIdentityRetry() async -> IdentityOutcome {
        guard let gateway else { return .notNeeded(.signedOut) }
        return await gateway.requestIdentityRetry().awaitValue()
    }

    func commit(_ envelope: StampedSubscriptionCommit) {
        switch SubscriptionStampReducer.disposition(incoming: envelope, lastAccepted: state.lastAccepted) {
        case .ignoreExactDuplicate: return
        case .drop(let violation): relay.report(violation); return
        case .apply: state.lastAccepted = envelope
        }
        let effects = applyStateEvent(envelope.event)
        effects.violations.forEach { relay.report($0) }
        perform(effects)
    }
}

private extension PurchaseService {
    func performProofMutation<Value>(_ mutation: () -> Value) -> Value {
        expiryScheduler.cancelWake()
        return mutation()
    }

    func applyStateEvent(_ event: SubscriptionCommitEvent) -> PurchaseStateEffects {
        switch event {
        case .offeringsLoaded(let lease, _) where lease == state.currentReadyLease,
             .offeringsUnavailable(let lease, _) where lease == state.currentReadyLease:
            let clock = self.clock
            return state.apply(event, now: { clock.now() })
        default:
            let clock = self.clock
            return performProofMutation { state.apply(event, now: { clock.now() }) }
        }
    }

    func perform(_ effects: PurchaseStateEffects) {
        if let expiry = effects.expiry, case .rearm(let delay) = expiry {
            expiryScheduler.replaceWake(after: delay)
        }
        if let event = effects.analytics { analytics.track(event) }
    }

    func reevaluateEntitlementExpiry() {
        let now = state.proof?.isActive == true && state.proof?.expirationDate != nil
            ? clock.now()
            : nil
        let expiry = performProofMutation { state.reevaluate(now: now) }
        perform(PurchaseStateEffects(expiry: expiry, analytics: nil, violations: []))
    }
}

#if DEBUG
extension PurchaseService {
    var diagnostics: PurchaseServiceDiagnostics {
        PurchaseServiceDiagnostics(
            lastAcceptedStamp: state.lastAccepted?.stamp,
            lastAcceptedEvent: state.lastAccepted?.event,
            currentReadyLease: state.currentReadyLease,
            proofIsPresent: state.proof != nil,
            proofIsActive: state.proof?.isActive == true,
            proofExpiration: state.proof?.expirationDate,
            storedSelection: state.storedSelection,
            accountRevision: state.accountRevision
        )
    }
}
#endif
