import Foundation
import SwiftData
import Testing
@testable import Garage

@MainActor
struct SyncServiceTests {
    @Test func enqueue_marksOfflineAndPersistsItem() throws {
        let service = SyncService()
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        try service.enqueue(
            Payload(value: "queued"),
            collectionPath: "vehicles",
            documentId: "vehicle",
            operation: .create,
            modelContext: context
        )

        let queue = try context.fetch(FetchDescriptor<SyncQueueItem>())
        let payload = try JSONDecoder().decode(Payload.self, from: queue[0].payloadData)
        #expect(service.currentStatus == .offline)
        #expect(queue.count == 1)
        #expect(payload == Payload(value: "queued"))
    }

    @Test func flush_removesSuccessfulItemsAndReturnsUpToDate() async throws {
        let service = SyncService()
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        try service.enqueue(
            Payload(value: "queued"),
            collectionPath: "vehicles",
            documentId: "vehicle",
            operation: .update,
            modelContext: context
        )
        var sawSyncing = false

        await service.flushQueue(modelContext: context) { item in
            sawSyncing = service.currentStatus == .syncing
            #expect(item.documentId == "vehicle")
        }

        #expect(sawSyncing)
        #expect(service.currentStatus == .idle)
        let queue = try context.fetch(FetchDescriptor<SyncQueueItem>())
        #expect(queue.isEmpty)
    }

    @Test func flush_retainsFailedItemsAndMarksNeedsAttention() async throws {
        let service = SyncService()
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        try service.enqueue(
            Payload(value: "queued"),
            collectionPath: "vehicles",
            documentId: "vehicle",
            operation: .delete,
            modelContext: context
        )

        await service.flushQueue(modelContext: context) { _ in
            throw SyncTestError.failed
        }

        let queue = try context.fetch(FetchDescriptor<SyncQueueItem>())
        #expect(service.currentStatus == .attentionNeeded)
        #expect(queue.count == 1)
        #expect(queue[0].lastAttemptAt != nil)
        #expect(queue[0].failureReason == SyncTestError.failed.localizedDescription)
    }

    private func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SyncQueueItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

private struct Payload: Codable, Equatable {
    var value: String
}

private enum SyncTestError: LocalizedError {
    case failed

    var errorDescription: String? { "simulated sync failure" }
}
