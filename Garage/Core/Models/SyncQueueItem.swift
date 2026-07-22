import Foundation
import SwiftData

struct SyncSessionToken: Sendable, Hashable, Equatable {
    let uid: String
    let generation: Int
}

struct SyncEvidenceToken: Sendable, Hashable, Equatable {
    let session: SyncSessionToken
    let epoch: Int
}

typealias SyncBarrierToken = SyncEvidenceToken

enum SyncConnectivity: Sendable, Equatable {
    case unknown
    case reachable
    case unreachable
}

enum SyncPresentationState: Sendable, Equatable {
    case checkingSync
    case syncing
    case savedOnThisIPhone
    case offlineCachedData
    case upToDate
    case needsAttention

    var label: String {
        switch self {
        case .checkingSync: return "Checking log sync"
        case .syncing: return "Syncing service log"
        case .savedOnThisIPhone: return "Saved on this iPhone"
        case .offlineCachedData: return "Offline"
        case .upToDate: return "Service log up to date"
        case .needsAttention: return "Log sync needs attention"
        }
    }
}

enum SyncProbeEvent: Sendable, Equatable {
    case envelope(VehicleSnapshotEnvelope)
    case failure(VehicleListenerError)
}

@MainActor
protocol SyncConnectivityMonitoring: AnyObject {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void)
    func cancel()
}

/// Firebase-free production identity seam for isolated tests.
@MainActor
struct SyncServiceProvider {
    static let production = SyncServiceProvider(resolve: { SyncService.shared })
    let resolve: () -> SyncService
}

enum SyncOperation: String, Codable, Sendable {
    case create
    case update
    case delete
}

/// Identifies one listener installed after a specific acknowledgement or barrier event.
struct SyncProbeToken: Sendable, Equatable {
    let evidence: SyncEvidenceToken
    let instanceID: UUID
}

extension SyncService {
    var currentStatus: SyncStatus {
        switch presentationState {
        case .checkingSync: return .idle
        case .syncing: return .syncing
        case .savedOnThisIPhone, .offlineCachedData: return .offline
        case .upToDate: return .upToDate
        case .needsAttention: return .attentionNeeded
        }
    }
}

enum SyncProbeDisposition: Sendable, Equatable {
    case continueListening
    case stopListening
    case ignored
}

@Model
final class SyncQueueItem {
    var id: String
    var collectionPath: String
    var documentId: String
    var payloadData: Data
    var operation: String
    var createdAt: Date
    var lastAttemptAt: Date?
    var failureReason: String?

    init(
        id: String = UUID().uuidString,
        collectionPath: String,
        documentId: String,
        payloadData: Data,
        operation: SyncOperation,
        createdAt: Date = .now,
        lastAttemptAt: Date? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.collectionPath = collectionPath
        self.documentId = documentId
        self.payloadData = payloadData
        self.operation = operation.rawValue
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.failureReason = failureReason
    }
}

@Model
final class DraftEntry {
    var id: String
    var vehicleId: String
    var entryType: String
    var payloadData: Data
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        vehicleId: String,
        entryType: EntryType,
        payloadData: Data,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.vehicleId = vehicleId
        self.entryType = entryType.rawValue
        self.payloadData = payloadData
        self.updatedAt = updatedAt
    }
}
