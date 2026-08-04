import Foundation
import Testing
@testable import Garage

/// A calendar file is handed to another app entirely, so "close enough" is not a category that
/// exists here: an unescaped comma silently truncates a title, and a mis-stamped DTSTART puts the
/// event on the wrong day in a calendar the owner then trusts.
struct ICSBuilderTests {
    /// 2026-08-03T12:00:00Z and 2026-09-01T16:30:45Z.
    private let stamp = Date(timeIntervalSince1970: 1_785_758_400)
    private let due = Date(timeIntervalSince1970: 1_788_280_245)

    private func reminder(
        id: String = "reminder-1",
        title: String = "Oil change",
        dueDate: Date?,
        repeatIntervalMonths: Int? = nil
    ) -> Reminder {
        Reminder(
            id: id, vehicleId: "vehicle", title: title, entryType: nil, dueDate: dueDate,
            dueMileage: nil, repeatIntervalMonths: repeatIntervalMonths, repeatIntervalMiles: nil,
            notes: nil, isProFeature: false, createdAt: nil, completedAt: nil
        )
    }

    private func lines(_ document: String) -> [String] {
        Array(document.components(separatedBy: "\r\n").dropLast())
    }

    @Test func aDatedReminderProducesTheExactDocument() throws {
        let document = try #require(ICSBuilder.makeCalendar(for: reminder(dueDate: due), stamped: stamp))

        #expect(document == """
            BEGIN:VCALENDAR\r
            VERSION:2.0\r
            PRODID:-//Garage//Reminder Export//EN\r
            CALSCALE:GREGORIAN\r
            BEGIN:VEVENT\r
            UID:reminder-1@garage\r
            DTSTAMP:20260803T120000Z\r
            DTSTART:20260901T163045Z\r
            SUMMARY:Oil change\r
            END:VEVENT\r
            END:VCALENDAR\r

            """)
    }

    /// Only reminders WITH a due date are exportable — a mileage-only reminder has no start.
    @Test func aReminderWithoutADueDateIsNotExportable() {
        #expect(ICSBuilder.makeCalendar(for: reminder(dueDate: nil), stamped: stamp) == nil)
        #expect(ICSBuilder.makeCalendar(for: reminder(dueDate: nil, repeatIntervalMonths: 6), stamped: stamp) == nil)
    }

    @Test func theSameInputAlwaysProducesTheSameBytes() {
        let subject = reminder(title: "Brake fluid", dueDate: due, repeatIntervalMonths: 24)
        let first = ICSBuilder.makeCalendar(for: subject, stamped: stamp)
        for _ in 0..<10 {
            #expect(ICSBuilder.makeCalendar(for: subject, stamped: stamp) == first)
        }
    }

    // MARK: - Timestamps

    /// The stored due date is already canonicalised to a local instant at save time; the export's
    /// job is only to state that instant in UTC, which is what the trailing Z means.
    @Test func timestampsAreUTCBasicFormatRegardlessOfTheAmbientTimeZone() {
        #expect(ICSBuilder.timestamp(Date(timeIntervalSince1970: 0)) == "19700101T000000Z")
        #expect(ICSBuilder.timestamp(due) == "20260901T163045Z")
        // One second before midnight UTC — the case that rolls the DATE over if the zone slips.
        #expect(ICSBuilder.timestamp(Date(timeIntervalSince1970: 1_788_307_199)) == "20260901T235959Z")
    }

    // MARK: - RRULE

    @Test func aRepeatIntervalBecomesAMonthlyRRULE() throws {
        let document = try #require(
            ICSBuilder.makeCalendar(for: reminder(dueDate: due, repeatIntervalMonths: 6), stamped: stamp)
        )
        #expect(lines(document).contains("RRULE:FREQ=MONTHLY;INTERVAL=6"))
    }

    @Test func noRepeatIntervalMeansNoRRULE() throws {
        let document = try #require(ICSBuilder.makeCalendar(for: reminder(dueDate: due), stamped: stamp))
        #expect(!lines(document).contains { $0.hasPrefix("RRULE") })
    }

    /// INTERVAL must be a positive integer; a non-positive stored value is dropped rather than
    /// written out as a rule some calendars reject by discarding the whole event.
    @Test func aNonPositiveRepeatIntervalIsDroppedRatherThanWrittenInvalid() throws {
        for months in [0, -3] {
            let document = try #require(
                ICSBuilder.makeCalendar(for: reminder(dueDate: due, repeatIntervalMonths: months), stamped: stamp)
            )
            #expect(!lines(document).contains { $0.hasPrefix("RRULE") })
        }
    }

    // MARK: - RFC 5545 text escaping

    @Test func backslashesSemicolonsCommasAndNewlinesAreEscaped() {
        #expect(ICSBuilder.escape("Oil, filter; and plugs") == "Oil\\, filter\\; and plugs")
        #expect(ICSBuilder.escape("line one\nline two") == "line one\\nline two")
        #expect(ICSBuilder.escape("line one\r\nline two") == "line one\\nline two")
        #expect(ICSBuilder.escape("carriage\rreturn") == "carriage\\nreturn")
    }

    /// The backslash must be escaped FIRST, or the ones introduced for commas and semicolons get
    /// escaped in turn and the reader sees a literal `\,` instead of a comma.
    @Test func aBackslashIsEscapedBeforeTheCharactersItIntroduces() {
        #expect(ICSBuilder.escape("back\\slash") == "back\\\\slash")
        #expect(ICSBuilder.escape("mix\\, and ;") == "mix\\\\\\, and \\;")
    }

    @Test func anEscapedTitleReachesTheSummaryLine() throws {
        let subject = reminder(title: "Oil, filter; check\nrear brakes", dueDate: due)
        let document = try #require(ICSBuilder.makeCalendar(for: subject, stamped: stamp))
        #expect(lines(document).contains("SUMMARY:Oil\\, filter\\; check\\nrear brakes"))
    }

    // MARK: - Line folding (§3.1)

    @Test func aShortLineIsNotFolded() {
        #expect(ICSBuilder.fold("SUMMARY:Oil change") == ["SUMMARY:Oil change"])
        #expect(ICSBuilder.fold(String(repeating: "a", count: 75)).count == 1)
    }

    @Test func aLongLineFoldsAtSeventyFiveOctetsWithLeadingSpaceContinuations() {
        let folded = ICSBuilder.fold("SUMMARY:" + String(repeating: "a", count: 200))
        #expect(folded.count > 1)
        #expect(folded.allSatisfy { $0.utf8.count <= ICSBuilder.maxOctetsPerLine })
        #expect(folded.dropFirst().allSatisfy { $0.hasPrefix(" ") })
        // Unfolding (drop the CRLF + one leading space) must return the original line.
        #expect(unfold(folded) == "SUMMARY:" + String(repeating: "a", count: 200))
    }

    /// Octets, not characters: a multi-byte character must never be split across the fold, which
    /// counting Characters alone would let happen at a 75-BYTE boundary.
    @Test func foldingCountsOctetsAndNeverSplitsAMultiByteCharacter() {
        let folded = ICSBuilder.fold("SUMMARY:" + String(repeating: "é", count: 60))
        #expect(folded.allSatisfy { $0.utf8.count <= ICSBuilder.maxOctetsPerLine })
        #expect(unfold(folded) == "SUMMARY:" + String(repeating: "é", count: 60))
    }

    /// The reader's half of §3.1: strip the leading space each continuation line carries.
    private func unfold(_ folded: [String]) -> String {
        folded.enumerated()
            .map { $0.offset == 0 ? $0.element : String($0.element.dropFirst()) }
            .joined()
    }

    @Test func aLongTitleIsFoldedInTheDocumentAndEveryLineFitsTheBudget() throws {
        let subject = reminder(title: String(repeating: "Replace the timing belt ", count: 12), dueDate: due)
        let document = try #require(ICSBuilder.makeCalendar(for: subject, stamped: stamp))
        #expect(lines(document).allSatisfy { $0.utf8.count <= ICSBuilder.maxOctetsPerLine })
        #expect(lines(document).contains { $0.hasPrefix(" ") })
    }

    @Test func everyLineIncludingTheLastIsCRLFTerminated() throws {
        let document = try #require(ICSBuilder.makeCalendar(for: reminder(dueDate: due), stamped: stamp))
        #expect(document.hasSuffix("END:VCALENDAR\r\n"))
        // No bare LF anywhere: a lone newline is what makes strict parsers reject the file.
        #expect(!document.components(separatedBy: "\r\n").contains { $0.contains("\n") })
    }
}
