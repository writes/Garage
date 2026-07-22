@preconcurrency import FirebaseFirestore
import Foundation

// MARK: - RULES-1 counted create (the server-authoritative cap batch)

extension VehicleService {
    /// RULES-1 counted create: the vehicle doc and the users/{uid} counter transition commit
    /// in ONE batch — the rules verify vehicleCount == prior+1 within the tier cap and the
    /// lastVehicleOp binding, which is what makes the cap server-authoritative.
    func commitCountedCreate(_ vehicle: Vehicle, uid: String, firestore: FirestoreService) async throws {
        let document = firestore.db.collection(FirestorePaths.vehicles).document(vehicle.id)
        let userDocument = firestore.db.collection(FirestorePaths.users).document(uid)
        let batch = firestore.db.batch()
        batch.setData(try firestore.encode(vehicle), forDocument: document)
        batch.setData([
            "vehicleCount": FieldValue.increment(Int64(1)),
            "lastVehicleOp": ["id": vehicle.id, "op": "create"]
        ], forDocument: userDocument, merge: true)
        do {
            try await batch.commit()
        } catch let error as NSError where error.domain == FirestoreErrorDomain
            && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            // The local precheck already passed, so this denial means the SERVER's view
            // disagrees with ours — most likely a still-undecremented counter from a recent
            // deletion (heal it), or a create raced from another device. Claiming "upgrade to
            // Pro" here would be a false upsell; say what actually happened instead.
            Task { await retryPendingPurges() }
            throw AppError.database(
                "Couldn't add the vehicle — your vehicle count is still syncing. Please try again in a moment."
            )
        }
    }
}
