import Foundation
import Network
import Observation
@MainActor private final class NetworkSyncConnectivityMonitor: SyncConnectivityMonitoring {
    private var monitor: NWPathMonitor?
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let state: SyncConnectivity = path.status == .satisfied ? .reachable : .unreachable
            Task { @MainActor in handler(state) }
        }
        monitor.start(queue: DispatchQueue(label: "Garage.SyncConnectivity"))
        self.monitor = monitor
    }
    func cancel() { monitor?.cancel(); monitor = nil }
}
@MainActor
@Observable final class SyncService {
    static let shared = SyncService()
    private(set) var presentationState: SyncPresentationState = .checkingSync
    private(set) var diagnosticMessage: String?
    private let monitorFactory: () -> any SyncConnectivityMonitoring
    private var activeSession: SyncSessionToken?
    private var generation = 0
    private var connectivity: SyncConnectivity = .unknown
    private var latestRegisteredEpoch = 0
    private var outstandingMutationTokens = Set<SyncEvidenceToken>()
    private var inFlightBarrierTokens = Set<SyncBarrierToken>()
    private var snapshotHasPendingWrites: Bool?
    private var acknowledgedEpoch: Int?
    private var barrierAcknowledgedEpoch: Int?
    private var postAcknowledgementServerFreshnessEpoch: Int?
    private var monitor: (any SyncConnectivityMonitoring)?
    private var barrierStarter: ((SyncSessionToken) -> Void)?
    private var probeStarter: ((SyncProbeToken) -> Task<Void, Never>)?
    private var probeEligibleToken: SyncEvidenceToken?
    private var probeRequestedToken: SyncEvidenceToken?
    private var activeProbeInstanceID: UUID?
    private var activeProbeTask: Task<Void, Never>?
    init(monitorFactory: (() -> any SyncConnectivityMonitoring)? = nil) {
        self.monitorFactory = monitorFactory ?? { NetworkSyncConnectivityMonitor() }
    }
    func activateSession(uid: String) -> SyncSessionToken {
        if let activeSession, activeSession.uid == uid {
            startMonitorIfNeeded(for: activeSession)
            return activeSession
        }
        invalidateCurrentSession()
        let session = SyncSessionToken(uid: uid, generation: generation)
        activeSession = session
        startMonitorIfNeeded(for: session)
        refreshPresentation()
        return session
    }
    func deactivateSession(_ session: SyncSessionToken) {
        guard activeSession == session else { return }
        invalidateCurrentSession()
    }
    func isActive(_ session: SyncSessionToken) -> Bool { activeSession == session }
    func bindProbeStarter(session: SyncSessionToken, starter: @escaping (SyncProbeToken) -> Task<Void, Never>) {
        guard activeSession == session else { return }
        probeStarter = starter
        requestEligibleProbe()
    }
    func bindBarrierStarter(session: SyncSessionToken, starter: @escaping (SyncSessionToken) -> Void) {
        guard activeSession == session else { return }
        barrierStarter = starter
    }
    func registerMutation(session: SyncSessionToken) -> SyncEvidenceToken? {
        guard activeSession == session else { return nil }
        clearProbeState()
        latestRegisteredEpoch += 1
        let token = SyncEvidenceToken(session: session, epoch: latestRegisteredEpoch)
        acknowledgedEpoch = nil
        barrierAcknowledgedEpoch = nil
        postAcknowledgementServerFreshnessEpoch = nil
        outstandingMutationTokens.insert(token)
        refreshPresentation()
        return token
    }
    func rollbackMutation(_ token: SyncEvidenceToken) {
        guard activeSession == token.session else { return }
        outstandingMutationTokens.remove(token)
        refreshPresentation()
    }
    func recordAcknowledgement(_ token: SyncEvidenceToken, message: String?) {
        guard activeSession == token.session else { return }
        outstandingMutationTokens.remove(token)
        if let message {
            recordFailure(session: token.session, message: message)
            return
        }
        guard token.epoch == latestRegisteredEpoch else { refreshPresentation(); return }
        acknowledgedEpoch = token.epoch
        makeProbeEligible(token)
    }
    /// Primary listener metadata is conservative evidence only; it can never make the state green.
    func recordSnapshotMetadata(session: SyncSessionToken, isFromCache: Bool, hasPendingWrites: Bool) {
        guard activeSession == session else { return }
        reduceMetadata(isFromCache: isFromCache, hasPendingWrites: hasPendingWrites)
    }
    func recordPrimarySnapshot(_ envelope: VehicleSnapshotEnvelope, session: SyncSessionToken) {
        guard activeSession == session else { return }
        latchDecodeDiagnostic(envelope.decodeFailureDocumentIDs)
        reduceMetadata(isFromCache: envelope.isFromCache, hasPendingWrites: envelope.hasPendingWrites)
    }
    func recordFailure(session: SyncSessionToken, message: String) {
        guard activeSession == session else { return }
        latchDiagnostic(message)
        refreshPresentation()
    }
    func recordConnectivity(_ state: SyncConnectivity, session: SyncSessionToken) {
        guard activeSession == session else { return }
        let becameReachable = connectivity != .reachable && state == .reachable
        connectivity = state
        if becameReachable { postAcknowledgementServerFreshnessEpoch = nil }
        refreshPresentation()
        if becameReachable { barrierStarter?(session) }
    }
    /// Registers barrier evidence before invocation, so a synchronous callback remains safe.
    func beginWriteBarrier(session: SyncSessionToken, using starter: (@escaping @Sendable (String?) -> Void) -> Void) {
        guard activeSession == session else { return }
        clearProbeState()
        postAcknowledgementServerFreshnessEpoch = nil
        refreshPresentation()
        let token = SyncBarrierToken(session: session, epoch: latestRegisteredEpoch)
        inFlightBarrierTokens.insert(token)
        starter { [weak self, token] message in
            Task { @MainActor [weak self, token, message] in self?.recordBarrierResult(token, message: message) }
        }
    }
    func reduceProbe(_ event: SyncProbeEvent, token incoming: SyncProbeToken) -> SyncProbeDisposition {
        guard incoming.evidence == probeRequestedToken,
              incoming.evidence == currentEvidence,
              incoming.instanceID == activeProbeInstanceID else { return .ignored }
        switch event {
        case .envelope(let envelope):
            latchDecodeDiagnostic(envelope.decodeFailureDocumentIDs)
            snapshotHasPendingWrites = envelope.hasPendingWrites
            if !envelope.isFromCache && !envelope.hasPendingWrites {
                postAcknowledgementServerFreshnessEpoch = incoming.evidence.epoch
                refreshPresentation()
                return .stopListening
            }
            refreshPresentation()
            return .continueListening
        case .failure(let error):
            latchDiagnostic(error.message)
            refreshPresentation()
            return .stopListening
        }
    }
    func finishProbe(_ incoming: SyncProbeToken) {
        guard probeRequestedToken == incoming.evidence, activeProbeInstanceID == incoming.instanceID else { return }
        activeProbeTask = nil
        activeProbeInstanceID = nil
    }
}
private extension SyncService {
    private func recordBarrierResult(_ token: SyncBarrierToken, message: String?) {
        guard activeSession == token.session else { return }
        inFlightBarrierTokens.remove(token)
        if let message {
            recordFailure(session: token.session, message: message)
            return
        }
        guard token.epoch == latestRegisteredEpoch else { refreshPresentation(); return }
        barrierAcknowledgedEpoch = token.epoch
        makeProbeEligible(token)
    }
    private var currentEvidence: SyncEvidenceToken? {
        activeSession.map { SyncEvidenceToken(session: $0, epoch: latestRegisteredEpoch) }
    }
    private func makeProbeEligible(_ token: SyncEvidenceToken) {
        probeEligibleToken = token
        requestEligibleProbe()
        refreshPresentation()
    }
    /// No suspension occurs between installing identity and storing the returned main-actor task.
    private func requestEligibleProbe() {
        guard let evidence = probeEligibleToken, evidence == currentEvidence,
              probeRequestedToken != evidence, let probeStarter else { return }
        probeRequestedToken = evidence
        let instanceID = UUID()
        activeProbeInstanceID = instanceID
        let token = SyncProbeToken(evidence: evidence, instanceID: instanceID)
        activeProbeTask = probeStarter(token)
    }
    private func reduceMetadata(isFromCache: Bool, hasPendingWrites: Bool) {
        snapshotHasPendingWrites = hasPendingWrites
        refreshPresentation()
    }
    private func latchDecodeDiagnostic(_ documentIDs: [String]) {
        guard !documentIDs.isEmpty else { return }
        latchDiagnostic("Could not decode vehicle records: " + documentIDs.joined(separator: ","))
    }
    private func latchDiagnostic(_ message: String) {
        if diagnosticMessage == nil { diagnosticMessage = message }
    }
    private var hasKnownPendingWrites: Bool { !outstandingMutationTokens.isEmpty || snapshotHasPendingWrites == true }
    private func startMonitorIfNeeded(for session: SyncSessionToken) {
        guard monitor == nil else { return }
        let monitor = monitorFactory()
        self.monitor = monitor
        monitor.start { [weak self, session] state in self?.recordConnectivity(state, session: session) }
    }
    private func clearProbeState(unbind: Bool = false) {
        activeProbeTask?.cancel()
        activeProbeTask = nil
        activeProbeInstanceID = nil
        probeEligibleToken = nil
        probeRequestedToken = nil
        if unbind { probeStarter = nil }
    }
    private func invalidateCurrentSession() {
        monitor?.cancel()
        monitor = nil
        barrierStarter = nil
        clearProbeState(unbind: true)
        activeSession = nil
        generation += 1
        connectivity = .unknown
        latestRegisteredEpoch = 0
        outstandingMutationTokens.removeAll()
        inFlightBarrierTokens.removeAll()
        snapshotHasPendingWrites = nil
        acknowledgedEpoch = nil
        barrierAcknowledgedEpoch = nil
        postAcknowledgementServerFreshnessEpoch = nil
        diagnosticMessage = nil
        refreshPresentation()
    }
    private func refreshPresentation() {
        guard activeSession != nil else { presentationState = .checkingSync; return }
        if diagnosticMessage != nil { presentationState = .needsAttention; return }
        if hasKnownPendingWrites {
            presentationState = connectivity == .reachable ? .syncing : .savedOnThisIPhone
        } else if connectivity == .unreachable {
            presentationState = .offlineCachedData
        } else if connectivity == .reachable,
                  snapshotHasPendingWrites == false,
                  acknowledgedEpoch == latestRegisteredEpoch || barrierAcknowledgedEpoch == latestRegisteredEpoch,
                  postAcknowledgementServerFreshnessEpoch == latestRegisteredEpoch {
            presentationState = .upToDate
        } else {
            presentationState = .checkingSync
        }
    }
}
