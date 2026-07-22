import Testing
@testable import Garage
@MainActor struct SyncServiceTests {
    @Test func activation_isIdempotentAndStartsOneMonitor() {
        let monitor = SyncMonitorSpy()
        let service = SyncService(monitorFactory: { monitor })
        #expect(service.activateSession(uid: "user") == service.activateSession(uid: "user"))
        #expect(monitor.startCount == 1)
        #expect(monitor.cancelCount == 0)
    }
    @Test func acknowledgementNeedsCausalProbeAfterPreAckServerSnapshot() throws {
        let monitor = SyncMonitorSpy(), factory = SyncProbeStarter()
        let service = SyncService(monitorFactory: { monitor })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        service.recordPrimarySnapshot(serverEnvelope(), session: session)
        let evidence = try #require(service.registerMutation(session: session))
        service.recordAcknowledgement(evidence, message: nil)
        #expect(factory.tokens.count == 1)
        #expect(service.presentationState == .checkingSync)
        #expect(service.reduceProbe(.envelope(serverEnvelope()), token: factory.tokens[0]) == .stopListening)
        #expect(service.presentationState == .upToDate)
    }
    @Test func synchronousBarrierCallbackRegistersEvidenceBeforeInvokingProbe() async {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        service.beginWriteBarrier(session: session) { completion in completion(nil) }
        await factory.waitForTokens(1)
        #expect(factory.tokens.count == 1)
        #expect(service.presentationState == .checkingSync)
        _ = service.reduceProbe(.envelope(serverEnvelope()), token: factory.tokens[0])
        #expect(service.presentationState == .upToDate)
    }
    @Test func nonReachableTransitionsStartOneBarrierAndNeedItsCausalProbe() async {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.bindBarrierStarter(session: session) { [weak service] active in
            guard let service else { return }
            service.beginWriteBarrier(session: active) { $0(nil) }
        }
        service.recordConnectivity(.reachable, session: session)
        #expect(service.presentationState == .checkingSync)
        await factory.waitForTokens(1)
        #expect(factory.tokens.count == 1)
        #expect(service.presentationState == .checkingSync)
        #expect(service.reduceProbe(.envelope(serverEnvelope()), token: factory.tokens[0]) == .stopListening)
        #expect(service.presentationState == .upToDate)
        service.recordConnectivity(.reachable, session: session)
        #expect(factory.tokens.count == 1)
        service.recordConnectivity(.unreachable, session: session)
        service.recordConnectivity(.reachable, session: session)
        await factory.waitForTokens(2)
        #expect(factory.tokens.count == 2)
        #expect(service.presentationState == .checkingSync)
    }
    @Test func cacheAndPendingProbeMetadataCannotTurnTheStateGreen() throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        service.recordAcknowledgement(try #require(service.registerMutation(session: session)), message: nil)
        let key = factory.tokens[0]
        #expect(service.reduceProbe(.envelope(envelope(cache: true, pending: false)), token: key) == .continueListening)
        #expect(service.presentationState == .checkingSync)
        #expect(service.reduceProbe(.envelope(envelope(cache: false, pending: true)), token: key) == .continueListening)
        #expect(service.presentationState == .syncing)
    }
    @Test func duplicateEvidenceStartsOneProbeAndLateBindingConsumesOneEligibleToken() throws {
        let service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.recordConnectivity(.reachable, session: session)
        let evidence = try #require(service.registerMutation(session: session))
        service.recordAcknowledgement(evidence, message: nil)
        #expect(service.presentationState == .checkingSync)
        let factory = SyncProbeStarter()
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordAcknowledgement(evidence, message: nil)
        #expect(factory.tokens.count == 1)
    }
    @Test func newMutationAndUIDTransitionCancelFirstMonitorAndMakeOldProbeResultsInert() throws {
        let factory = SyncProbeStarter(), firstMonitor = SyncMonitorSpy(), secondMonitor = SyncMonitorSpy()
        var monitors = [firstMonitor, secondMonitor]
        let service = SyncService(monitorFactory: { monitors.removeFirst() })
        let first = service.activateSession(uid: "first")
        service.bindProbeStarter(session: first, starter: factory.start)
        service.recordConnectivity(.reachable, session: first)
        service.recordAcknowledgement(try #require(service.registerMutation(session: first)), message: nil)
        let stale = factory.tokens[0]
        _ = service.registerMutation(session: first)
        #expect(service.reduceProbe(.envelope(serverEnvelope()), token: stale) == .ignored)
        let second = service.activateSession(uid: "second")
        firstMonitor.emit(.reachable)
        #expect(service.reduceProbe(.failure(VehicleListenerError(message: "late")), token: stale) == .ignored)
        #expect(first != second)
        #expect(firstMonitor.cancelCount == 1)
        #expect(secondMonitor.startCount == 1)
        #expect(service.presentationState == .checkingSync)
    }
}
extension SyncServiceTests {
    @Test func labelsFollowPendingConnectivityMatrixAndSnapshotPendingEvidence() {
        for testCase in SyncPresentationLabelCase.all {
            let service = SyncService(monitorFactory: { SyncPassiveMonitor() })
            let session = service.activateSession(uid: "user")
            if testCase.hasPendingWrites { _ = service.registerMutation(session: session) }
            service.recordConnectivity(testCase.connectivity, session: session)
            #expect(service.presentationState.label == testCase.expectedLabel)
        }
        let service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.recordSnapshotMetadata(session: session, isFromCache: true, hasPendingWrites: true)
        service.recordConnectivity(.reachable, session: session)
        #expect(service.presentationState == .syncing)
        service.recordConnectivity(.unreachable, session: session)
        #expect(service.presentationState == .savedOnThisIPhone)
        service.recordSnapshotMetadata(session: session, isFromCache: true, hasPendingWrites: false)
        #expect(service.presentationState == .offlineCachedData)
    }
    @Test func reconnectAndRelaunchBarrierInvalidatePreviouslyGreenFreshness() throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.bindBarrierStarter(session: session) { [weak service] active in
            guard let service else { return }
            service.beginWriteBarrier(session: active) { $0(nil) }
        }
        service.recordConnectivity(.reachable, session: session)
        service.recordAcknowledgement(try #require(service.registerMutation(session: session)), message: nil)
        _ = service.reduceProbe(.envelope(serverEnvelope()), token: factory.tokens[0])
        #expect(service.presentationState == .upToDate)
        service.recordConnectivity(.unreachable, session: session)
        service.recordConnectivity(.reachable, session: session)
        #expect(service.presentationState == .checkingSync)
        service.beginWriteBarrier(session: session) { $0(nil) }
        #expect(service.presentationState == .checkingSync)
    }
    @Test func mutationRegisteredAfterBarrierNeedsItsOwnAcknowledgementAndProbe() async throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        var barrierCompletion: (@Sendable (String?) -> Void)?
        service.beginWriteBarrier(session: session) { completion in barrierCompletion = completion }
        #expect(barrierCompletion != nil)
        let mutation = try #require(service.registerMutation(session: session))
        #expect(service.presentationState == .syncing)
        #expect(factory.tokens.isEmpty)
        service.recordAcknowledgement(mutation, message: nil)
        await factory.waitForTokens(1)
        #expect(factory.tokens.count == 1)
        #expect(factory.tokens[0].evidence == mutation)
        #expect(service.reduceProbe(.envelope(serverEnvelope()), token: factory.tokens[0]) == .stopListening)
        #expect(service.presentationState == .upToDate)
    }
    @Test func currentProbeRestoresGreenButTypedFailureLatchesAttention() async throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        service.recordAcknowledgement(try #require(service.registerMutation(session: session)), message: nil)
        let token = factory.tokens[0]
        _ = service.reduceProbe(.envelope(serverEnvelope()), token: token)
        #expect(service.presentationState == .upToDate)
        service.beginWriteBarrier(session: session) { $0(nil) }
        await factory.waitForTokens(2)
        let current = try #require(factory.tokens.last)
        _ = service.reduceProbe(.failure(VehicleListenerError(message: "listener failed")), token: current)
        #expect(service.presentationState == .needsAttention)
        #expect(service.diagnosticMessage == "listener failed")
    }
    @Test func rollbackNeverRestoresOldGreenAndFailuresClearOnlyAtSessionBoundaries() throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        service.recordAcknowledgement(try #require(service.registerMutation(session: session)), message: nil)
        _ = service.reduceProbe(.envelope(serverEnvelope()), token: factory.tokens[0])
        #expect(service.presentationState == .upToDate)
        let rolledBack = try #require(service.registerMutation(session: session))
        service.rollbackMutation(rolledBack)
        #expect(service.presentationState == .checkingSync)
        service.recordFailure(session: session, message: "rejected")
        service.recordConnectivity(.unreachable, session: session)
        service.recordConnectivity(.reachable, session: session)
        service.recordPrimarySnapshot(serverEnvelope(), session: session)
        #expect(service.diagnosticMessage == "rejected")
        #expect(service.presentationState == .needsAttention)
        let replacement = service.activateSession(uid: "replacement")
        #expect(service.diagnosticMessage == nil)
        service.recordFailure(session: replacement, message: "second rejection")
        service.deactivateSession(replacement)
        #expect(service.diagnosticMessage == nil)
        #expect(service.presentationState == .checkingSync)
    }
    @Test func staleProbeFailureAndCancellationEquivalentDoNotLatchAttention() throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        service.recordAcknowledgement(try #require(service.registerMutation(session: session)), message: nil)
        let stale = factory.tokens[0]
        _ = service.registerMutation(session: session)
        #expect(service.reduceProbe(.failure(VehicleListenerError(message: "late")), token: stale) == .ignored)
        // Cancellation creates no event, so its only observable result is this unchanged state.
        #expect(service.presentationState == .syncing)
    }
    @Test func deactivationUnbindsAndOldFinishCannotClearNewProbe() throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let first = service.activateSession(uid: "user")
        service.bindProbeStarter(session: first, starter: factory.start)
        service.recordConnectivity(.reachable, session: first)
        service.recordAcknowledgement(try #require(service.registerMutation(session: first)), message: nil)
        let old = factory.tokens[0]
        service.deactivateSession(first)
        #expect(service.reduceProbe(.envelope(serverEnvelope()), token: old) == .ignored)
        let second = service.activateSession(uid: "user")
        service.bindProbeStarter(session: second, starter: factory.start)
        service.recordConnectivity(.reachable, session: second)
        service.recordAcknowledgement(try #require(service.registerMutation(session: second)), message: nil)
        let current = factory.tokens[1]
        service.finishProbe(old)
        #expect(service.reduceProbe(.envelope(serverEnvelope()), token: current) == .stopListening)
    }
    @Test func malformedProbeEnvelopeLatchesBeforeServerMetadataAndNeverAutoClears() throws {
        let factory = SyncProbeStarter(), service = SyncService(monitorFactory: { SyncPassiveMonitor() })
        let session = service.activateSession(uid: "user")
        service.bindProbeStarter(session: session, starter: factory.start)
        service.recordConnectivity(.reachable, session: session)
        service.recordAcknowledgement(try #require(service.registerMutation(session: session)), message: nil)
        let malformed = VehicleSnapshotEnvelope(
            vehicles: [],
            isFromCache: false,
            hasPendingWrites: false,
            decodeFailureDocumentIDs: ["b", "a"]
        )
        _ = service.reduceProbe(.envelope(malformed), token: factory.tokens[0])
        #expect(service.diagnosticMessage == "Could not decode vehicle records: a,b")
        #expect(service.presentationState == .needsAttention)
        service.recordPrimarySnapshot(serverEnvelope(), session: session)
        #expect(service.diagnosticMessage == "Could not decode vehicle records: a,b")
    }
    private func envelope(cache: Bool, pending: Bool) -> VehicleSnapshotEnvelope {
        .init(vehicles: [], isFromCache: cache, hasPendingWrites: pending)
    }
    private func serverEnvelope() -> VehicleSnapshotEnvelope { envelope(cache: false, pending: false) }
}
