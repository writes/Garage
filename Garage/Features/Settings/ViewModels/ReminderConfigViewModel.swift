import Foundation
import Observation

@MainActor
@Observable
final class ReminderConfigViewModel {
    private let reminderService: ReminderService

    var title = "Oil change"
    var dueMileage = ""
    var dueMonths = ""
    private(set) var error: AppError?

    init(reminderService: ReminderService = .shared) {
        self.reminderService = reminderService
    }

    func save(vehicleId: String) async -> Bool {
        do {
            let reminder = Reminder(
                id: UUID().uuidString,
                vehicleId: vehicleId,
                title: title,
                dueMileage: Int(dueMileage),
                repeatIntervalMonths: Int(dueMonths),
                repeatIntervalMiles: Int(dueMileage),
                isProFeature: false
            )
            try await reminderService.save(reminder)
            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }
}
