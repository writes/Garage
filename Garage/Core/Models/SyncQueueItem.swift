import Foundation
import SwiftData

enum SyncOperation: String, Codable, Sendable {
    case create
    case update
    case delete
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
