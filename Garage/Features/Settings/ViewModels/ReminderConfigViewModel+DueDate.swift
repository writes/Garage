import Foundation

// MARK: - Due-date math (split out of ReminderConfigViewModel.swift to stay under the file cap)

extension ReminderConfigViewModel {
    /// One-tap due date, identical in create and edit mode. It writes only the two form properties
    /// the toggle and the picker already write, so `reminderToSave`'s field-preservation contract
    /// is untouched by construction.
    func applyDueDatePreset(_ preset: ReminderDueDatePreset, now: Date = .now, calendar: Calendar = .current) {
        hasDueDate = true
        dueDate = preset.dueDate(now: now, calendar: calendar)
    }

    /// Tomorrow at 09:00 local. Internal (not private) and parameterized over `now`/`calendar` —
    /// exposed for direct unit testing, mirroring ReminderNotificationCoordinator.plan's
    /// precedent. Falls back to now+24h in the (practically unreachable) case the calendar can't
    /// produce a startOfDay/9h instant.
    static func defaultDueDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let tomorrowAt9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else {
            return now.addingTimeInterval(24 * 60 * 60)
        }
        return tomorrowAt9
    }

    /// Canonicalizes whatever DAY the picker landed on to a fixed local time-of-day (09:00), so a
    /// future day always yields a future instant regardless of what wall-clock time-of-day the
    /// picker's value happens to carry (BLOCKER fix: an untouched picker previously kept
    /// `Date.now`'s exact instant, which read as already-past moments later). A TODAY selection
    /// that still normalizes into the past must not silently skip scheduling — it falls forward
    /// to now+5min instead. Internal, exposed for direct unit testing.
    static func canonicalDueInstant(for pickedDate: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let normalized = calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: calendar.startOfDay(for: pickedDate)
        ) ?? pickedDate
        if normalized > now {
            return normalized
        }
        if calendar.isDate(pickedDate, inSameDayAs: now) {
            return now.addingTimeInterval(5 * 60)
        }
        return normalized
    }
}
