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

    @Test func downloadData_hermeticModeReturnsTheStoredBytes() async throws {
        let service = EntryAttachmentService(uuidProvider: { "fixed-uuid" })
        let bytes = Data([0x25, 0x50, 0x44, 0x46]) // "%PDF"
        let path = try await service.uploadPDFAttachment(bytes, uid: "u", vehicleId: "v", entryId: "e")

        let downloaded = try await service.downloadData(for: path)
        #expect(downloaded == bytes)
    }

    @Test func downloadData_hermeticModeThrowsForAnUnknownPath() async {
        let service = EntryAttachmentService()
        await #expect(throws: (any Error).self) {
            _ = try await service.downloadData(for: "users/u/entry-attachments/v/e/missing.pdf")
        }
    }

    @Test func downloadData_seededTestUploadsAreReadableWithoutAnUploadCall() async throws {
        let bytes = Data([0x01, 0x02, 0x03])
        let service = EntryAttachmentService(testUploads: ["users/u/entry-attachments/v/e/seed.pdf": bytes])
        let downloaded = try await service.downloadData(for: "users/u/entry-attachments/v/e/seed.pdf")
        #expect(downloaded == bytes)
    }
}
