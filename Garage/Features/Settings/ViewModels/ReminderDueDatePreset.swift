import Foundation

/// The three one-tap due dates offered above the reminder form's date picker, covering the common
/// service cadences. Labels read "In 3 months" rather than a bare "3 months" because the row sits
/// directly under "Repeat every X months": a bare interval there is read as the repeat field, not
/// as a due date (cross-critic finding).
enum ReminderDueDatePreset: Int, CaseIterable, Identifiable, Sendable {
    case threeMonths = 3
    case sixMonths = 6
    case oneYear = 12

    var id: Int { rawValue }

    /// The raw value IS the month count, so the accessibility identifiers key off a number that
    /// cannot drift from the display copy.
    var months: Int { rawValue }

    var label: String {
        switch self {
        case .threeMonths: return "In 3 months"
        case .sixMonths: return "In 6 months"
        case .oneYear: return "In 1 year"
        }
    }

    /// `months` out from TODAY at 09:00 local — deliberately the same shape
    /// `ReminderConfigViewModel.canonicalDueInstant` normalizes to, so the save-time
    /// canonicalization is a fixed point and cannot move the day the user tapped for. Adding to
    /// `startOfDay` rather than to `now` is what keeps the picked time-of-day out of the result;
    /// a month-end source day clamps (Jan 31 + 3 months → Apr 30).
    ///
    /// Falls back to the form's tomorrow-9am default, NEVER to `now`: an instant that is already
    /// past by the time save() runs is the documented BLOCKER class (see
    /// ReminderConfigViewModel.dueDate). `@MainActor` only because that fallback is a static of a
    /// `@MainActor` view model; every caller (form, view model, tests) is main-actor anyway.
    @MainActor
    func dueDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        guard let shifted = calendar.date(byAdding: .month, value: months, to: calendar.startOfDay(for: now)),
              let shiftedAt9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: shifted) else {
            return ReminderConfigViewModel.defaultDueDate(now: now, calendar: calendar)
        }
        return shiftedAt9
    }
}
