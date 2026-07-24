import Foundation

/// A picked-but-not-yet-uploaded attachment. Bytes are already prepared (downsampled, for
/// images) by the time one of these exists — AttachmentPicker does that work before ever
/// appending one.
enum PendingAttachmentKind: Equatable, Sendable {
    case image
    case pdf
}

struct PendingAttachment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: PendingAttachmentKind
    let data: Data
    /// Shown in the pending row: the source filename for a PDF, a generic label for a photo
    /// (PhotosPicker never exposes a stable filename for a photo-library pick).
    let displayName: String
}

/// Pending-attachment lifecycle for EntryFormViewModel: queue picks locally, upload only at
/// save() time (see save() in EntryFormViewModel.swift), and defer already-uploaded removals
/// until the entry write they're attached to actually succeeds.
extension EntryFormViewModel {
    func addPendingImage(_ data: Data) {
        pendingAttachments.append(PendingAttachment(kind: .image, data: data, displayName: "Photo"))
    }

    func addPendingPDF(_ data: Data, filename: String) {
        pendingAttachments.append(PendingAttachment(kind: .pdf, data: data, displayName: filename))
    }

    func removePendingAttachment(_ id: PendingAttachment.ID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Removing an already-uploaded attachment during an edit only queues the removal —
    /// applyQueuedAttachmentRemovals runs the actual Storage delete after a successful save, so
    /// backing out of the edit (or a failed save) never destroys evidence the live entry still
    /// references.
    func queueAttachmentRemoval(_ path: String) {
        attachmentPaths.removeAll { $0 == path }
        queuedAttachmentRemovals.append(path)
    }

    /// Uploads every pending attachment in order, appending each returned path to
    /// attachmentPaths as it lands. On any failure, best-effort deletes whatever DID upload in
    /// THIS call (so a retry never leaves an orphaned blob no entry references) and rethrows —
    /// save() aborts with nothing written. pendingAttachments is only cleared on full success, so
    /// a retry doesn't lose the user's picks.
    func uploadPendingAttachments(uid: String, vehicleId: String, entryId: String) async throws {
        guard !pendingAttachments.isEmpty else { return }
        var uploadedPaths: [String] = []
        defer { uploadingAttachmentID = nil }
        do {
            for pending in pendingAttachments {
                uploadingAttachmentID = pending.id
                let path = try await upload(pending, uid: uid, vehicleId: vehicleId, entryId: entryId)
                uploadedPaths.append(path)
            }
        } catch {
            await entryAttachmentService.deleteAttachments(paths: uploadedPaths)
            throw error
        }
        attachmentPaths.append(contentsOf: uploadedPaths)
        pendingAttachments.removeAll()
    }

    /// Applied only after the entry write succeeds — see save()'s ordering.
    func applyQueuedAttachmentRemovals() async {
        guard !queuedAttachmentRemovals.isEmpty else { return }
        await entryAttachmentService.deleteAttachments(paths: queuedAttachmentRemovals)
        queuedAttachmentRemovals.removeAll()
    }

    private func upload(
        _ pending: PendingAttachment, uid: String, vehicleId: String, entryId: String
    ) async throws -> String {
        switch pending.kind {
        case .image:
            return try await entryAttachmentService.uploadImageAttachment(
                pending.data, uid: uid, vehicleId: vehicleId, entryId: entryId
            )
        case .pdf:
            return try await entryAttachmentService.uploadPDFAttachment(
                pending.data, uid: uid, vehicleId: vehicleId, entryId: entryId
            )
        }
    }
}
