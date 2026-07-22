@preconcurrency import FirebaseFirestore
import Foundation

struct VehicleSnapshotEnvelope: Sendable, Equatable {
    let vehicles: [Vehicle]; let isFromCache: Bool
    let hasPendingWrites: Bool; let decodeFailureDocumentIDs: [String]
    init(vehicles: [Vehicle], isFromCache: Bool, hasPendingWrites: Bool, decodeFailureDocumentIDs: [String] = []) {
        self.vehicles = vehicles
        self.isFromCache = isFromCache; self.hasPendingWrites = hasPendingWrites
        self.decodeFailureDocumentIDs = decodeFailureDocumentIDs.sorted()
    }
}
struct VehicleListenerError: Error, Sendable, Equatable, LocalizedError {
    let message: String; var errorDescription: String? { message }
}
enum VehicleListenerEvent: Sendable, Equatable {
    case snapshot(VehicleSnapshotEnvelope), failure(VehicleListenerError), finished
}
protocol VehicleListenerRemoval: AnyObject { func remove() }
@MainActor struct VehicleListenerFactory {
    let register: (String, @escaping @Sendable (VehicleListenerEvent) -> Void) -> any VehicleListenerRemoval
}

/// Stream termination is the only removal path; this locked box makes it idempotent off-actor.
private final class ListenerRemovalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: (any VehicleListenerRemoval)?
    private var removed = false
    func install(_ handle: any VehicleListenerRemoval) {
        lock.lock()
        if removed { lock.unlock(); handle.remove(); return }
        self.handle = handle; lock.unlock()
    }
    func remove() {
        lock.lock()
        guard !removed else { lock.unlock(); return }
        removed = true; let handle = self.handle
        self.handle = nil; lock.unlock()
        handle?.remove()
    }
}

private final class FirebaseVehicleListenerRemoval: VehicleListenerRemoval {
    private let registration: ListenerRegistration
    init(registration: ListenerRegistration) { self.registration = registration }
    func remove() { registration.remove() }
}

// MARK: - Stream construction (implementation detail of listenToVehicles)

extension VehicleService {
    static func singleVehicleStream(_ vehicles: [Vehicle]) -> VehicleStream {
        AsyncThrowingStream { continuation in
            continuation.yield(VehicleSnapshotEnvelope(vehicles: vehicles, isFromCache: false, hasPendingWrites: false))
            continuation.finish()
        }
    }
    static func failedVehicleStream(_ error: VehicleListenerError) -> VehicleStream {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
    static func liveVehicleStream(uid: String, factory: VehicleListenerFactory) -> VehicleStream {
        AsyncThrowingStream { continuation in
            let removalBox = ListenerRemovalBox()
            continuation.onTermination = { _ in removalBox.remove() }
            let handle = factory.register(uid) { event in
                switch event {
                case .snapshot(let envelope): continuation.yield(envelope)
                case .failure(let error): continuation.finish(throwing: error)
                case .finished: continuation.finish()
                }
            }
            removalBox.install(handle)
        }
    }
    static func makeFirebaseListenerFactory(firestore: FirestoreService) -> VehicleListenerFactory {
        VehicleListenerFactory { uid, handler in
            let query = firestore.db.collection(FirestorePaths.vehicles)
                .whereField("userId", isEqualTo: uid)
                .order(by: "displayOrder")
                .limit(to: 20)
            let registration = query.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                let event: VehicleListenerEvent
                if let error {
                    event = .failure(VehicleListenerError(message: error.localizedDescription))
                } else if let snapshot {
                    var vehicles: [Vehicle] = []
                    var failedIDs: [String] = []
                    for document in snapshot.documents {
                        do {
                            let vehicle = try firestore.decode(Vehicle.self, from: document.data())
                            // Tombstoned vehicles (RULES-1 soft delete) are hidden everywhere.
                            if vehicle.deletedAt == nil { vehicles.append(vehicle) }
                        } catch {
                            failedIDs.append(document.documentID)
                        }
                    }
                    event = .snapshot(VehicleSnapshotEnvelope(
                        vehicles: vehicles, isFromCache: snapshot.metadata.isFromCache,
                        hasPendingWrites: snapshot.metadata.hasPendingWrites,
                        decodeFailureDocumentIDs: failedIDs
                    ))
                } else {
                    event = .failure(VehicleListenerError(message: "The vehicle listener returned no snapshot."))
                }
                handler(event)
            }
            return FirebaseVehicleListenerRemoval(registration: registration)
        }
    }
}
