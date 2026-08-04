import Foundation
import Testing
@testable import Garage

/// The temp-file half of the calendar export. The filename is user-visible in the share sheet and
/// is built from free text, so the allowlist is a correctness property, not a nicety.
@MainActor
struct ReminderCalendarExportTests {
    private let due = Date(timeIntervalSince1970: 1_788_280_245)

    private func reminder(title: String = "Oil change", dueDate: Date?) -> Reminder {
        Reminder(
            id: "reminder-1", vehicleId: "vehicle", title: title, entryType: nil, dueDate: dueDate,
            dueMileage: nil, repeatIntervalMonths: nil, repeatIntervalMiles: nil, notes: nil,
            isProFeature: false, createdAt: nil, completedAt: nil
        )
    }

    @Test func writingADatedReminderProducesAReadableICSFileKeyedToThatReminder() throws {
        let artifact = try #require(try ReminderCalendarExport.write(reminder(dueDate: due)))
        defer { ReminderCalendarExport.remove(artifact) }

        #expect(artifact.id == "reminder-1")
        #expect(artifact.url.pathExtension == "ics")
        #expect(artifact.url.lastPathComponent.hasPrefix(ReminderCalendarExport.filenamePrefix))
        let written = try String(contentsOf: artifact.url, encoding: .utf8)
        #expect(written.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(written.contains("UID:reminder-1@garage"))
    }

    @Test func aReminderWithoutADueDateWritesNothing() throws {
        #expect(try ReminderCalendarExport.write(reminder(dueDate: nil)) == nil)
    }

    @Test func removingAnArtifactDeletesTheFile() throws {
        let artifact = try #require(try ReminderCalendarExport.write(reminder(dueDate: due)))
        #expect(FileManager.default.fileExists(atPath: artifact.url.path))

        ReminderCalendarExport.remove(artifact)

        #expect(!FileManager.default.fileExists(atPath: artifact.url.path))
    }

    // MARK: - Filename slug

    @Test func theSlugKeepsLettersAndNumbersAndCollapsesEverythingElse() {
        #expect(ReminderCalendarExport.slug("Oil change") == "oil-change")
        #expect(ReminderCalendarExport.slug("Brake fluid — 2 year") == "brake-fluid-2-year")
    }

    /// A title is free text. A path separator, a leading dot, or a title made entirely of
    /// punctuation must not become part of a filesystem path.
    @Test func theSlugCannotProduceAPathOrAnEmptyName() {
        #expect(!ReminderCalendarExport.slug("../../etc/passwd").contains("/"))
        #expect(!ReminderCalendarExport.slug("../../etc/passwd").contains("."))
        #expect(ReminderCalendarExport.slug("///") == "reminder")
        #expect(ReminderCalendarExport.slug("") == "reminder")
    }

    @Test func theSlugIsLengthCapped() {
        let slug = ReminderCalendarExport.slug(String(repeating: "verylongtitle", count: 20))
        #expect(slug.count == ReminderCalendarExport.maxSlugLength)
    }
}
