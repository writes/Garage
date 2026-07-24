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
    /// Backs the management list above the create form (D: reminders lifecycle) — every
    /// reminder for the vehicle, completed or not, soonest-due first via ReminderService.fetchAll.
    private(set) var reminders: [Reminder] = []
    private(set) var isLoading = false
    /// Mirrors LogViewModel.reloadToken: review finding — without it, an in-flight load()
    /// racing a NEWER load() (e.g. rapid vehicle switches) could let the stale response's
    /// `reminders`/`error` overwrite what the newer call already resolved.
    private var loadToken = 0

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
            await load(vehicleId: vehicleId)
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    func load(vehicleId: String) async {
        loadToken &+= 1
        let token = loadToken
        isLoading = true
        defer { if token == loadToken { isLoading = false } }
        do {
            let loaded = try await reminderService.fetchAll(vehicleId: vehicleId)
            guard token == loadToken else { return }
            reminders = loaded
            error = nil
        } catch {
            guard token == loadToken else { return }
            self.error = AppError(from: error)
        }
    }

    func delete(_ reminder: Reminder) async {
        do {
            try await reminderService.delete(reminder)
            reminders.removeAll { $0.id == reminder.id }
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    func markCompleted(_ reminder: Reminder) async {
        do {
            try await reminderService.markCompleted(reminder)
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[index].completedAt = .now
            }
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
