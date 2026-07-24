import Foundation

/// Identifies a QuickLook-ready PDF: `id` is the storage path (stable/unique per attachment),
/// `url` points at the session temp file PDFPreviewTempFile just wrote, `filename` drives both
/// the temp file's name and the preview sheet's navigation title.
struct PDFPreviewItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let filename: String
}

/// Single-preview temp-file discipline for QuickLook: at most one file lives on disk at a time,
/// under its own subdirectory of the session temp dir. Mirrors ExportViewModel's temp-artifact
/// discipline (Garage/Features/Settings/ViewModels/ExportViewModel.swift), sized down — a
/// QuickLook preview is transient and never shared/persisted the way an export is, so wiping the
/// whole subdirectory before every write is a simpler and still-sufficient "no unbounded
/// accumulation" guarantee than per-file live-URL tracking + an abandoned-file sweep would be.
///
/// Split out of AttachmentDetailRow.swift (its original home) into Core/Utilities alongside
/// Constants.swift: EntryDetailView now owns the download/write orchestration (the concurrent-tap
/// race fix), and `removeAll()` is also called from the app-launch and sign-out choke points, so
/// this is no longer a Log-feature-only concern.
enum PDFPreviewTempFile {
    private static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "garage-attachment-previews", isDirectory: true
        )
    }

    static func write(_ data: Data, filename: String) throws -> URL {
        let directory = Self.directory
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .completeFileProtection)
        return url
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
