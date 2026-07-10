import Observation

struct DashboardContent {
    var entries: [FirestoreEntry]
    var wearItems: [WearItem]
    var reminders: [Reminder]
    var warranties: [Warranty]
    var recalls: [Recall]
}

@MainActor
@Observable
final class DashboardViewModel {
    private let entryService: EntryService
    private let wearService: WearService
    private let reminderService: ReminderService
    private let warrantyService: WarrantyService
    private let contentLoader: ((String) async throws -> DashboardContent)?

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
        warrantyService: WarrantyService = .shared,
        contentLoader: ((String) async throws -> DashboardContent)? = nil
    ) {
        self.entryService = entryService
        self.wearService = wearService
        self.reminderService = reminderService
        self.warrantyService = warrantyService
        self.contentLoader = contentLoader
    }

    func loadDashboard(vehicleId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let contentLoader {
                apply(try await contentLoader(vehicleId))
                error = nil
                return
            }
            async let entries = entryService.fetchRecent(vehicleId: vehicleId)
            async let wear = wearService.fetchDashboard(vehicleId: vehicleId)
            async let reminders = reminderService.fetchUpcoming(vehicleId: vehicleId)
            async let warranties = warrantyService.fetchWarranties(vehicleId: vehicleId)
            async let recalls = warrantyService.fetchRecalls(vehicleId: vehicleId)

            apply(
                DashboardContent(
                    entries: try await entries,
                    wearItems: try await wear,
                    reminders: try await reminders,
                    warranties: try await warranties,
                    recalls: try await recalls
                )
            )
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    private func apply(_ content: DashboardContent) {
        recentEntries = content.entries
        wearItems = content.wearItems
        upcomingReminders = content.reminders
        hasActiveWarranty = content.warranties.contains(where: {
            ($0.expirationDate ?? $0.coverageEnd ?? .distantPast) >= .now
        })
        openRecalls = content.recalls.filter { $0.status == .outstanding }.count
    }
}
