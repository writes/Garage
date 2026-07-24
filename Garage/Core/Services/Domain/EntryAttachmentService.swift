@preconcurrency import FirebaseStorage
import Foundation
import Observation

/// Real attachments pipeline (external audit's top product-truth gap: "attachments retain
/// filenames rather than evidence"). Uploads/deletes/resolves already-prepared bytes only —
/// downsampling happens earlier, in AttachmentImageProcessor, before a photo ever reaches here.
/// Storage path shape is fixed by the existing rules (firebase.storage.rules: users/{uid}/** is
/// owner-only, <=25MB, image/pdf content types) and the deleteAccount Storage cascade, both of
/// which already cover anything under users/{uid}/ without a rules change:
/// users/{uid}/entry-attachments/{vehicleId}/{entryId}/{uuid}.{ext} (StoragePaths.entryAttachment).
@MainActor
@Observable
final class EntryAttachmentService {
    static let shared = EntryAttachmentService()

    private let rootReferenceProvider: () -> StorageReference
    private let isLocalDemoMode: () -> Bool
    private let uuidProvider: () -> String
    #if DEBUG
    private var testUploads: [String: Data]?
    /// Fault injection for the upload-failure/cleanup path (EntryFormViewModel+Attachments.swift
    /// deletes whatever DID upload in the same batch and rethrows) — matches VehicleService's
    /// updateInterceptor precedent. Called once per upload, before the path is recorded.
    private let testUploadInterceptor: (() throws -> Void)?
    #endif
    /// Demo mode has no real Storage, and the picker that would populate this is hidden there
    /// (EntryFormScaffold checks AppRuntime.isLocalDemoMode before showing it) — this branch is
    /// defensive-only, matching VehicleService/EntryService's mode pattern, not reachable via the UI today.
    private static var demoUploads: [String: Data] = [:]

    private init() {
        // Lazy, resolved only on first actual use — constructing this must never touch Firebase
        // pre-configure (the deleteAccount launch-crash lesson).
        rootReferenceProvider = { Storage.storage().reference() }
        isLocalDemoMode = { AppRuntime.isLocalDemoMode }
        uuidProvider = { UUID().uuidString }
        #if DEBUG
        testUploadInterceptor = nil
        #endif
    }

#if DEBUG
    init(
        testUploads: [String: Data] = [:],
        uuidProvider: @escaping () -> String = { UUID().uuidString },
        testUploadInterceptor: (() throws -> Void)? = nil
    ) {
        rootReferenceProvider = { fatalError("Hermetic EntryAttachmentService must not resolve live Storage") }
        isLocalDemoMode = { false }
        self.uuidProvider = uuidProvider
        self.testUploads = testUploads
        self.testUploadInterceptor = testUploadInterceptor
    }
#endif

    func uploadImageAttachment(
        _ data: Data, uid: String, vehicleId: String, entryId: String
    ) async throws -> String {
        try await upload(data, contentType: "image/jpeg", uid: uid, vehicleId: vehicleId, entryId: entryId)
    }

    func uploadPDFAttachment(
        _ data: Data, uid: String, vehicleId: String, entryId: String
    ) async throws -> String {
        try await upload(data, contentType: "application/pdf", uid: uid, vehicleId: vehicleId, entryId: entryId)
    }

    /// Best-effort: an entry delete or an in-edit attachment removal must not block on Storage's
    /// success. An orphaned blob is a cheap, unlinked cost; a stuck delete/save flow is not.
    func deleteAttachments(paths: [String]) async {
        guard !paths.isEmpty else { return }
        #if DEBUG
        if var testUploads {
            for path in paths { testUploads[path] = nil }
            self.testUploads = testUploads
            return
        }
        #endif
        if isLocalDemoMode() {
            for path in paths { Self.demoUploads[path] = nil }
            return
        }
        let root = rootReferenceProvider()
        for path in paths {
            do {
                try await root.child(path).delete()
            } catch {
                AppLogger.shared.error("Attachment delete failed for \(path): \(error.localizedDescription)")
            }
        }
    }

    /// EntryDetailView's image thumbnails resolve this into an AsyncImage URL. Hermetic/demo
    /// modes return a placeholder URL — nothing there actually serves the bytes back, which is
    /// fine: those paths never render through real AsyncImage/QuickLook UI.
    func downloadURL(for path: String) async throws -> URL {
        #if DEBUG
        if testUploads != nil {
            return Self.placeholderURL(for: path)
        }
        #endif
        if isLocalDemoMode() {
            return Self.placeholderURL(for: path)
        }
        return try await rootReferenceProvider().child(path).downloadURL()
    }

    private static func placeholderURL(for path: String) -> URL {
        URL(string: "https://example.invalid/\(path)") ?? URL(fileURLWithPath: "/dev/null")
    }

#if DEBUG
    /// Test-only read-back of the hermetic store (uploadedPathsForTesting), matching
    /// VehicleService/EntryService's precedent of exposing DEBUG-gated hooks for assertions the
    /// public API otherwise has no way to observe.
    func uploadedPathsForTesting() -> Set<String> {
        Set((testUploads ?? [:]).keys)
    }
#endif

    private func upload(
        _ data: Data, contentType: String, uid: String, vehicleId: String, entryId: String
    ) async throws -> String {
        let fileExtension = contentType == "application/pdf" ? "pdf" : "jpg"
        let path = StoragePaths.entryAttachment(
            userId: uid, vehicleId: vehicleId, entryId: entryId,
            filename: "\(uuidProvider()).\(fileExtension)"
        )
        #if DEBUG
        if var testUploads {
            try testUploadInterceptor?()
            testUploads[path] = data
            self.testUploads = testUploads
            return path
        }
        #endif
        if isLocalDemoMode() {
            Self.demoUploads[path] = data
            return path
        }
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        _ = try await rootReferenceProvider().child(path).putDataAsync(data, metadata: metadata)
        return path
    }
}
