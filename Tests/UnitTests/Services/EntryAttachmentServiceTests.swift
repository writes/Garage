import Foundation
import Testing
@testable import Garage

@MainActor
struct EntryAttachmentServiceTests {
    @Test func uploadImageAttachment_pathMatchesTheFixedStorageShape() async throws {
        let service = EntryAttachmentService(uuidProvider: { "fixed-uuid" })
        let path = try await service.uploadImageAttachment(
            Data([0x01]), uid: "user-1", vehicleId: "vehicle-1", entryId: "entry-1"
        )
        #expect(path == "users/user-1/entry-attachments/vehicle-1/entry-1/fixed-uuid.jpg")
    }

    @Test func uploadPDFAttachment_usesAPDFExtension() async throws {
        let service = EntryAttachmentService(uuidProvider: { "fixed-uuid" })
        let path = try await service.uploadPDFAttachment(
            Data([0x01]), uid: "user-1", vehicleId: "vehicle-1", entryId: "entry-1"
        )
        #expect(path == "users/user-1/entry-attachments/vehicle-1/entry-1/fixed-uuid.pdf")
    }

    @Test func distinctUploads_underTheSameEntryGetDistinctPaths() async throws {
        var counter = 0
        let service = EntryAttachmentService(uuidProvider: {
            counter += 1
            return "uuid-\(counter)"
        })
        let first = try await service.uploadImageAttachment(Data(), uid: "u", vehicleId: "v", entryId: "e")
        let second = try await service.uploadImageAttachment(Data(), uid: "u", vehicleId: "v", entryId: "e")
        #expect(first != second)
        #expect(service.uploadedPathsForTesting() == [first, second])
    }

    @Test func deleteAttachments_removesFromTheHermeticStore() async throws {
        let service = EntryAttachmentService(uuidProvider: { "fixed-uuid" })
        let path = try await service.uploadImageAttachment(Data(), uid: "u", vehicleId: "v", entryId: "e")
        #expect(service.uploadedPathsForTesting() == [path])

        await service.deleteAttachments(paths: [path])
        #expect(service.uploadedPathsForTesting().isEmpty)
    }

    @Test func deleteAttachments_emptyPathsIsANoopAndDoesNotThrow() async {
        let service = EntryAttachmentService()
        await service.deleteAttachments(paths: [])
        #expect(service.uploadedPathsForTesting().isEmpty)
    }

    @Test func downloadURL_hermeticModeReturnsAPlaceholderRatherThanThrowing() async throws {
        let service = EntryAttachmentService(uuidProvider: { "fixed-uuid" })
        let path = try await service.uploadImageAttachment(Data(), uid: "u", vehicleId: "v", entryId: "e")
        let url = try await service.downloadURL(for: path)
        #expect(url.absoluteString.contains(path))
    }

    @Test func seededTestUploads_areVisibleAtConstruction() {
        let service = EntryAttachmentService(testUploads: ["users/u/entry-attachments/v/e/seed.jpg": Data()])
        #expect(service.uploadedPathsForTesting() == ["users/u/entry-attachments/v/e/seed.jpg"])
    }
}
