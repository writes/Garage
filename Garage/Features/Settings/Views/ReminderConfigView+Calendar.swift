import SwiftUI

// MARK: - Calendar export (.ics hand-off, not an EventKit sync — see ICSBuilder)

extension ReminderConfigView {
    /// Offered only on a DATED reminder: a mileage-only reminder has no start instant, so there is
    /// no event to export — the same reason the form warns it can never send an alert.
    @ViewBuilder
    func calendarButton(for reminder: Reminder) -> some View {
        if reminder.dueDate != nil {
            Button {
                prepareCalendarArtifact(for: reminder)
            } label: {
                Label("Add to Calendar", systemImage: "calendar")
            }
            .tint(Theme.Colors.primary)
            .accessibilityIdentifier("reminder.calendar.\(reminder.id)")
        }
    }

    /// Two steps — build, then share — mirroring ExportView's CSV and PDF flow, where the
    /// ShareLink appears only once there is a real file behind it.
    @ViewBuilder
    func calendarShareRow(for reminder: Reminder) -> some View {
        if let artifact = calendarArtifact, artifact.id == reminder.id {
            ShareLink(item: artifact.url) {
                Label("Share calendar event", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("reminder.calendar.share.\(reminder.id)")
        }
        if calendarExportFailedID == reminder.id {
            Text("Couldn't build the calendar event.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("reminder.calendar.error.\(reminder.id)")
        }
    }

    func prepareCalendarArtifact(for reminder: Reminder) {
        // One pending artifact at a time: the previous file is deleted rather than left to
        // accumulate in the temp directory for the life of the process.
        discardCalendarArtifact()
        do {
            calendarArtifact = try ReminderCalendarExport.write(reminder)
        } catch {
            AppLogger.shared.error("Reminder calendar export failed: \(error.localizedDescription)")
        }
        // A nil artifact from a non-throwing write means the reminder had no due date, which the
        // button already excludes — either way there is nothing to share, so say so.
        calendarExportFailedID = calendarArtifact == nil ? reminder.id : nil
    }

    func discardCalendarArtifact() {
        ReminderCalendarExport.remove(calendarArtifact)
        calendarArtifact = nil
        calendarExportFailedID = nil
    }

    /// Only safe while nothing is live — `removeAbandoned` treats every matching file as orphaned.
    func sweepAbandonedCalendarFiles() {
        guard calendarArtifact == nil else { return }
        ReminderCalendarExport.removeAbandoned()
    }
}
