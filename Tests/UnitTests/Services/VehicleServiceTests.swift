import Foundation
import Testing
@testable import Garage

@MainActor
struct VehicleServiceTests {
    @Test func freeUser_isBlockedAtVehicleCap() async {
        let service = hermeticService([vehicle(id: "existing")])
        do { _ = try await service.createVehicle(vehicle(id: "new"))
            Issue.record("Expected the free vehicle cap to reject the second vehicle")
        } catch { #expect(error as? AppError == .vehicleLimitReached) }
    }
    @Test func freeUser_canCreateVehicleImmediatelyBelowCap() async throws {
        let service = hermeticService([]), created = try await service.createVehicle(vehicle(id: "first"))
        let vehicles = try await service.fetchVehicles()
        #expect(created.id == "first"); #expect(vehicles.map(\.id) == ["first"])
    }
    @Test func proUser_canCreateVehicleImmediatelyBelowCap() async throws {
        let vehicles = (0..<(Constants.maxProVehicles - 1)).map { vehicle(id: "existing-\($0)") }
        let service = hermeticService(vehicles, isPro: true)
        _ = try await service.createVehicle(vehicle(id: "fifth"))
        #expect(try await service.fetchVehicles().count == Constants.maxProVehicles)
    }
    @Test func proUser_isBlockedAtVehicleCap() async {
        let service = hermeticService((0..<Constants.maxProVehicles).map { vehicle(id: "existing-\($0)") }, isPro: true)
        do { _ = try await service.createVehicle(vehicle(id: "sixth"))
            Issue.record("Expected the Pro vehicle cap to reject the sixth vehicle")
        } catch { #expect(error as? AppError == .vehicleLimitReached) }
    }
    @Test func listenerEnvelopePreservesCacheAndPendingMetadata() async throws {
        let factory = VehicleListenerFactorySpy(), service = listenerService(factory, uidProvider: factory.resolveUID)
        let stream = service.listenToVehicles()
        #expect(factory.uidProviderCalls == 1); #expect(factory.receivedUID == "resolved-user")
        let cached = VehicleSnapshotEnvelope(
            vehicles: [vehicle(id: "cached")], isFromCache: true, hasPendingWrites: true)
        factory.emit(.snapshot(cached))
        var iterator = stream.makeAsyncIterator(); let envelope = try await iterator.next()
        #expect(envelope?.vehicles.map(\.id) == ["cached"])
        #expect(envelope?.isFromCache == true); #expect(envelope?.hasPendingWrites == true)
    }
    @Test func malformedEnvelopeRetainsValidVehiclesAndSortedDiagnosticIDs() async throws {
        let factory = VehicleListenerFactorySpy(), service = listenerService(factory)
        var iterator = service.listenToVehicles().makeAsyncIterator()
        factory.emit(.snapshot(VehicleSnapshotEnvelope(vehicles: [vehicle(id: "valid")], isFromCache: true,
            hasPendingWrites: false, decodeFailureDocumentIDs: ["z-bad", "a-bad"])))
        let envelope = try await iterator.next()
        #expect(envelope?.vehicles.map(\.id) == ["valid"])
        #expect(envelope?.decodeFailureDocumentIDs == ["a-bad", "z-bad"]); #expect(factory.handle.removeCount == 0)
    }
    @Test func correctedEnvelopeStillArrivesAfterMalformedEnvelope() async throws {
        let factory = VehicleListenerFactorySpy(), service = listenerService(factory)
        var iterator = service.listenToVehicles().makeAsyncIterator()
        factory.emit(.snapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: true, hasPendingWrites: false,
            decodeFailureDocumentIDs: ["bad"])))
        _ = try await iterator.next()
        let fixed = VehicleSnapshotEnvelope(
            vehicles: [vehicle(id: "fixed")], isFromCache: false, hasPendingWrites: false)
        factory.emit(.snapshot(fixed))
        let corrected = try await iterator.next()
        #expect(corrected?.vehicles.map(\.id) == ["fixed"]); #expect(factory.handle.removeCount == 0)
    }
    @Test func causalConsumerKeepsOneRegistrationThroughCacheAndPendingUntilServerFreshness() async {
        let factory = VehicleListenerFactorySpy(), service = listenerService(factory)
        do {
            let stream = service.listenToVehicles()
            let task = Task {
                do {
                    for try await envelope in stream {
                        if !envelope.isFromCache && !envelope.hasPendingWrites { return }
                    }
                } catch {}
            }
            await Task.yield()
            factory.emit(.snapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: true, hasPendingWrites: false)))
            factory.emit(.snapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: false, hasPendingWrites: true)))
            #expect(factory.registrationCount == 1); #expect(factory.handle.removeCount == 0)
            factory.emit(.snapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: false, hasPendingWrites: false)))
            await task.value
        }
        #expect(factory.handle.removeCount == 1)
    }
    @Test func ordinaryOfflineMetadataNeverRegistersASecondListenerOrRetries() {
        let factory = VehicleListenerFactorySpy(), stream = listenerService(factory).listenToVehicles()
        factory.emit(.snapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: true, hasPendingWrites: false)))
        factory.emit(.snapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: false, hasPendingWrites: true)))
        #expect(factory.registrationCount == 1); withExtendedLifetime(stream) {}
    }
    @Test func primaryMalformedDiagnosticPrecedesMetadataAndCleanMetadataCannotClearIt() {
        let sync = SyncService(monitorFactory: { PassiveVehicleMonitor() }), session = sync.activateSession(uid: "user")
        sync.recordConnectivity(.reachable, session: session)
        sync.recordPrimarySnapshot(VehicleSnapshotEnvelope(vehicles: [], isFromCache: false, hasPendingWrites: false,
            decodeFailureDocumentIDs: ["bad"]), session: session)
        #expect(sync.diagnosticMessage == "Could not decode vehicle records: bad")
        let clean = VehicleSnapshotEnvelope(vehicles: [], isFromCache: false, hasPendingWrites: false)
        sync.recordPrimarySnapshot(clean, session: session)
        #expect(sync.diagnosticMessage == "Could not decode vehicle records: bad")
        #expect(sync.presentationState == .needsAttention)
    }
    @Test func listenerFailureExplicitlyFinishesThrowing() async {
        let factory = VehicleListenerFactorySpy(), stream = listenerService(factory).listenToVehicles()
        let expected = VehicleListenerError(message: "decode failed")
        factory.emit(.failure(expected)); var iterator = stream.makeAsyncIterator()
        do { _ = try await iterator.next(); Issue.record("Expected failure event to finish the stream by throwing")
        } catch { #expect(error as? VehicleListenerError == expected) }
        #expect(factory.handle.removeCount == 1)
        factory.emit(.finished); factory.emit(.failure(expected)); #expect(factory.handle.removeCount == 1)
    }
    @Test func listenerTerminationRemovesTheRegistrationExactlyOnce() async {
        let factory = VehicleListenerFactorySpy(), stream = listenerService(factory).listenToVehicles()
        let task = Task { do { for try await _ in stream {} } catch {} }
        await Task.yield(); factory.emit(.failure(VehicleListenerError(message: "finished"))); await task.value
        #expect(factory.handle.removeCount == 1)
    }
    @Test func nonCancellationErrorRacingAfterCancellationIsIgnoredByConsumer() async {
        let factory = VehicleListenerFactorySpy(), stream = listenerService(factory).listenToVehicles()
        let result = ListenerConsumerResult()
        let task = Task {
            do { for try await _ in stream where Task.isCancelled { return }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) { result.failure = error.localizedDescription }
            }
        }
        await Task.yield(); task.cancel()
        factory.emit(.failure(VehicleListenerError(message: "late non-cancellation error")))
        await task.value; #expect(result.failure == nil); #expect(factory.handle.removeCount == 1)
    }
    @Test func hermeticVehicleStreamNeverConstructsLiveFactory() async throws {
        let factory = VehicleListenerFactorySpy()
        let service = VehicleService(testVehicles: [vehicle(id: "hermetic")],
            purchaseService: PurchaseService(testIsPro: false),
            listenerFactory: factory.factory, uidProvider: { fatalError("Hermetic stream resolved UID") })
        var iterator = service.listenToVehicles(uid: "bound-user").makeAsyncIterator()
        let envelope = try await iterator.next()
        #expect(envelope?.vehicles.map(\.id) == ["hermetic"]); #expect(envelope?.isFromCache == false)
        #expect(envelope?.hasPendingWrites == false); #expect(factory.registrationCount == 0)
    }
    @Test func boundListenerPassesExactUIDWithoutResolvingProvider() async throws {
        let factory = VehicleListenerFactorySpy()
        let service = listenerService(factory, uidProvider: { fatalError("Bound listener resolved UID") })
        var iterator = service.listenToVehicles(uid: "bound-user").makeAsyncIterator()
        #expect(factory.receivedUID == "bound-user"); factory.emit(.finished)
        #expect(try await iterator.next() == nil); #expect(factory.handle.removeCount == 1)
    }
    @Test func listenerFinishedReturnsNilAndRemovesOnce() async throws {
        let factory = VehicleListenerFactorySpy(), stream = listenerService(factory).listenToVehicles()
        factory.emit(.finished); var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == nil); #expect(factory.handle.removeCount == 1)
        factory.emit(.finished); factory.emit(.failure(VehicleListenerError(message: "late")))
        #expect(factory.handle.removeCount == 1)
    }
    @Test func synchronousFinishedBeforeHandleReturnRemovesLateHandleOnce() async throws {
        let factory = VehicleListenerFactorySpy(); factory.eventDuringRegistration = .finished
        var iterator = listenerService(factory).listenToVehicles().makeAsyncIterator()
        #expect(try await iterator.next() == nil); #expect(factory.handle.removeCount == 1)
    }
    @Test func synchronousFailureBeforeHandleReturnThrowsAndRemovesLateHandleOnce() async {
        let factory = VehicleListenerFactorySpy(), expected = VehicleListenerError(message: "synchronous")
        factory.eventDuringRegistration = .failure(expected)
        var iterator = listenerService(factory).listenToVehicles().makeAsyncIterator()
        do { _ = try await iterator.next(); Issue.record("Expected synchronous failure")
        } catch { #expect(error as? VehicleListenerError == expected) }
        #expect(factory.handle.removeCount == 1)
    }
    @Test func cancellationRemovesOnceAndSerialLateEventsRemainInert() async throws {
        let factory = VehicleListenerFactorySpy(), service = listenerService(factory)
        let ready = OneShotSignal(), drained = OneShotSignal(), result = ListenerConsumerResult()
        let task = Task { @MainActor in
            let failure: String? = await {
                let stream = service.listenToVehicles(); var iterator = stream.makeAsyncIterator(); ready.signal()
                do { _ = try await iterator.next(); return nil
                } catch where Task.isCancelled { return nil
                } catch { return error.localizedDescription }
            }()
            result.failure = failure; drained.signal()
        }
        try await awaitSignal(ready); task.cancel(); try await awaitSignal(drained); await task.value
        #expect(result.failure == nil); #expect(factory.handle.removeCount == 1)
        factory.emit(.finished); factory.emit(.failure(VehicleListenerError(message: "late")))
        #expect(factory.handle.removeCount == 1)
    }
    private func hermeticService(_ vehicles: [Vehicle], isPro: Bool = false) -> VehicleService {
        VehicleService(testVehicles: vehicles, purchaseService: PurchaseService(testIsPro: isPro))
    }
    private func listenerService(_ factory: VehicleListenerFactorySpy,
                                 uidProvider: @escaping () -> String? = { "test-user" }) -> VehicleService {
        VehicleService(listenerFactory: factory.factory, uidProvider: uidProvider)
    }
    private func vehicle(id: String) -> Vehicle {
        Vehicle(id: id, userId: "user", nickname: id, make: "Garage", model: "Test", year: 2026, currentOdometer: 1)
    }
}

@MainActor
private final class VehicleListenerFactorySpy {
    let handle = ListenerRemovalSpy()
    private(set) var registrationCount = 0, uidProviderCalls = 0
    private(set) var receivedUID: String?
    private var handler: (@Sendable (VehicleListenerEvent) -> Void)?
    var eventDuringRegistration: VehicleListenerEvent?
    func resolveUID() -> String? { uidProviderCalls += 1; return "resolved-user" }
    var factory: VehicleListenerFactory { VehicleListenerFactory { [weak self] uid, handler in
        guard let self else { fatalError("Listener factory deallocated") }
        registrationCount += 1; receivedUID = uid; self.handler = handler
        if let eventDuringRegistration { handler(eventDuringRegistration) }
        return handle
    } }
    func emit(_ event: VehicleListenerEvent) { handler?(event) }
}

private final class ListenerRemovalSpy: VehicleListenerRemoval {
    private let lock = NSLock(); private var _removeCount = 0
    var removeCount: Int { lock.lock(); defer { lock.unlock() }; return _removeCount }
    func remove() { lock.lock(); _removeCount += 1; lock.unlock() }
}

@MainActor
private final class OneShotSignal {
    private let stream: AsyncStream<Void>; private let continuation: AsyncStream<Void>.Continuation
    init() { let pair = AsyncStream<Void>.makeStream(); stream = pair.stream; continuation = pair.continuation }
    func signal() { continuation.yield() }
    func wait() async { var iterator = stream.makeAsyncIterator(); _ = await iterator.next() }
}

@MainActor
private func awaitSignal(_ gate: OneShotSignal) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        defer { group.cancelAll() }
        group.addTask { await gate.wait() }
        group.addTask { try await Task.sleep(nanoseconds: 1_000_000_000); throw ListenerTimeout.timedOut }
        // swiftlint:disable:next unused_optional_binding
        guard let _ = try await group.next() else { throw ListenerTimeout.timedOut }
    }
}

private enum ListenerTimeout: Error { case timedOut }
@MainActor private final class ListenerConsumerResult { var failure: String? }
@MainActor private final class PassiveVehicleMonitor: SyncConnectivityMonitoring {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {}
    func cancel() {}
}
