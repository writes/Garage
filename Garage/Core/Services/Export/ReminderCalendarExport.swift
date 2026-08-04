import Foundation

/// A written .ics file waiting to be shared, keyed by the reminder that produced it so a row can
/// tell whether the pending artifact is its own.
struct ReminderCalendarArtifact: Identifiable, Equatable {
    let id: String
    let url: URL
}

/// Temp-file plumbing for the reminder calendar export, mirroring ExportViewModel's CSV and PDF
/// artifacts: build into `temporaryDirectory`, hand the URL to a `ShareLink`, delete it when the
/// screen goes away. Nothing here is durable — a .ics is a hand-off, not a stored record.
@MainActor
enum ReminderCalendarExport {
    static let filenamePrefix = "garage-reminder-"
    static let fileExtension = "ics"
    /// Long enough to stay recognisable in the share sheet, short enough that a pathological title
    /// cannot approach a filesystem name limit.
    static let maxSlugLength = 40

    /// Nil when the reminder has no due date — see `ICSBuilder.makeCalendar`.
    static func write(_ reminder: Reminder, stamped stamp: Date = .now) throws -> ReminderCalendarArtifact? {
        guard let calendar = ICSBuilder.makeCalendar(for: reminder, stamped: stamp) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(filenamePrefix)\(slug(reminder.title)).\(fileExtension)")
        try Data(calendar.utf8).write(to: url, options: .atomic)
        return ReminderCalendarArtifact(id: reminder.id, url: url)
    }

    /// The filename is what the share sheet puts in front of the owner, so it comes from the
    /// title — but through a strict allowlist, because a title is free text and a path separator
    /// in a filename is a bug at best.
    static func slug(_ title: String) -> String {
        let allowed = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "reminder" : String(collapsed.prefix(maxSlugLength))
    }

    static func remove(_ artifact: ReminderCalendarArtifact?) {
        guard let artifact else { return }
        ExportViewModel.removeExportFile(artifact.url)
    }

    /// Sweeps .ics files left behind by a process death that never reached the disappear cleanup,
    /// reusing the same helper as the CSV and PDF launch sweeps. Callers must only run this while
    /// no artifact is live, since an empty live-set makes every match abandoned.
    static func removeAbandoned() {
        ExportViewModel.removeAbandonedExports(
            prefix: filenamePrefix, extension: fileExtension, liveURLs: []
        )
    }
}
