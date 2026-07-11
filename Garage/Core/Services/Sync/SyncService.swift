import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    private(set) var currentStatus: SyncStatus = .idle

    init() {}

    func enqueue<T: Encodable>(
        _ value: T,
        collectionPath: String,
        documentId: String,
        operation: SyncOperation,
        modelContext: ModelContext
    ) throws {
        let payloadData = try JSONEncoder().encode(value)
        let item = SyncQueueItem(
            collectionPath: collectionPath,
            documentId: documentId,
            payloadData: payloadData,
            operation: operation
        )
        modelContext.insert(item)
        currentStatus = .offline
    }

    func flushQueue(
        modelContext: ModelContext,
        handler: @escaping @MainActor (SyncQueueItem) async throws -> Void
    ) async {
        currentStatus = .syncing

        do {
            let queue = try modelContext.fetch(FetchDescriptor<SyncQueueItem>())
            for item in queue {
                do {
                    try await handler(item)
                    modelContext.delete(item)
                } catch {
                    item.lastAttemptAt = .now
                    item.failureReason = error.localizedDescription
                    currentStatus = .attentionNeeded
                }
            }

            if currentStatus != .attentionNeeded {
                currentStatus = .idle
            }
        } catch {
            currentStatus = .attentionNeeded
        }
    }
}
