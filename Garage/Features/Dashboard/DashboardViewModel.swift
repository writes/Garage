import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let entryService: EntryService
    private let wearService: WearService
    private let reminderService: ReminderService
    private let warrantyService: WarrantyService

    private(set) var recentEntries: [FirestoreEntry] = []
    private(set) var wearItems: [WearItem] = []
    private(set) var upcomingReminders: [Reminder] = []
    private(set) var openRecalls = 0
    private(set) var hasActiveWarranty = false
    private(set) var isLoading = false
    private(set) var error: AppError?

    init(
        entryService: EntryService = .shared,
        wearService: WearService = .shared,
        reminderService: ReminderService = .shared,
        warrantyService: WarrantyService = .shared
    ) {
        self.entryService = entryService
        self.wearService = wearService
        self.reminderService = reminderService
        self.warrantyService = warrantyService
    }

    func loadDashboard(vehicleId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let entries = entryService.fetchRecent(vehicleId: vehicleId)
            async let wear = wearService.fetchDashboard(vehicleId: vehicleId)
            async let reminders = reminderService.fetchUpcoming(vehicleId: vehicleId)
            async let warranties = warrantyService.fetchWarranties(vehicleId: vehicleId)
            async let recalls = warrantyService.fetchRecalls(vehicleId: vehicleId)

            recentEntries = try await entries
            wearItems = try await wear
            upcomingReminders = try await reminders
            let resolvedWarranties = try await warranties
            let resolvedRecalls = try await recalls
            hasActiveWarranty = resolvedWarranties.contains(where: {
                ($0.expirationDate ?? $0.coverageEnd ?? .distantPast) >= .now
            })
            openRecalls = resolvedRecalls.filter { $0.status == .outstanding }.count
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }
}
