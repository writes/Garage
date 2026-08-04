import Foundation

/// Builds a single-event iCalendar (RFC 5545) document for one reminder, for hand-off through the
/// share sheet.
///
/// Deliberately NOT an EventKit sync. Writing into the owner's calendar store needs a permission
/// prompt plus an ongoing two-way reconciliation — what happens when they move the event, or when
/// the reminder is edited afterwards — and this app has no answer for that yet. A .ics file works
/// with every calendar an owner might actually use, and leaves the copy under their control.
enum ICSBuilder {
    /// RFC 5545 §3.1: content lines are folded at 75 OCTETS, not characters, and continuation
    /// lines are introduced by a single leading space that counts against the same budget.
    static let maxOctetsPerLine = 75
    static let productIdentifier = "-//Garage//Reminder Export//EN"

    /// Nil when the reminder has no due date. An event with no start is not a calendar event, and
    /// a mileage-only reminder is precisely the case the form already warns can never be alerted
    /// on — exporting one as a dateless "event" would repeat that lie in another app.
    ///
    /// `stamp` is injected rather than read from the clock so the output is a pure function of its
    /// inputs and can be asserted byte-for-byte.
    static func makeCalendar(for reminder: Reminder, stamped stamp: Date) -> String? {
        guard let dueDate = reminder.dueDate else { return nil }
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:\(productIdentifier)",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            "UID:\(reminder.id)@garage",
            "DTSTAMP:\(timestamp(stamp))",
            "DTSTART:\(timestamp(dueDate))",
            "SUMMARY:\(escape(reminder.title))"
        ]
        // INTERVAL must be a positive integer. A zero or negative stored value is dropped rather
        // than written out as a malformed rule, which some calendars reject by discarding the
        // whole event instead of just the recurrence.
        if let months = reminder.repeatIntervalMonths, months > 0 {
            lines.append("RRULE:FREQ=MONTHLY;INTERVAL=\(months)")
        }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        // Every line, including the last, is CRLF-terminated (§3.1).
        return lines.flatMap(fold).map { $0 + "\r\n" }.joined()
    }

    /// RFC 5545 §3.3.11 TEXT escaping. The backslash MUST be replaced first: doing it later would
    /// escape the backslashes introduced by the other three replacements.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    /// UTC basic format (`19980118T230000Z`). Assembled from components rather than a
    /// `DateFormatter` so it carries no locale, no ambient calendar, and no shared mutable state
    /// that would need isolating.
    static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    /// Folds one content line to the octet budget, never splitting a multi-byte character — a
    /// title is free text, so an emoji or an accented word can straddle the boundary.
    static func fold(_ line: String) -> [String] {
        guard line.utf8.count > maxOctetsPerLine else { return [line] }
        var folded: [String] = []
        var current = ""
        var octets = 0
        // The first line spends all 75 octets on content; each continuation gives one up to the
        // leading space that marks it as a continuation.
        var budget = maxOctetsPerLine
        for character in line {
            let width = String(character).utf8.count
            if octets + width > budget {
                folded.append(current)
                current = ""
                octets = 0
                budget = maxOctetsPerLine - 1
            }
            current.append(character)
            octets += width
        }
        folded.append(current)
        return folded.enumerated().map { $0.offset == 0 ? $0.element : " " + $0.element }
    }
}
