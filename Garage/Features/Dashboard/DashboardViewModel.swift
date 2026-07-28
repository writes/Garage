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
    /// Vehicle + revision pair already reflected in the loaded content; a matching pair on the
    /// next call means no live write has bumped `VehicleDataRevisionStore` since, so the load is
    /// skipped. Tuples aren't Equatable-optional-friendly, hence the struct.
    private struct LoadKey: Equatable {
        let vehicleId: String
        let revision: Int
    }

    private let entryService: EntryService
    private let wearService: WearService
    private let reminderService: ReminderService
    private let warrantyService: WarrantyService
    private let revisionStore: VehicleDataRevisionStore
    private let gateEnabled: Bool
    private let contentLoader: ((String) async throws -> DashboardContent)?

    /// How far back the entry fetch reaches. The dashboard displays the newest few, but the
    /// maintenance advisor needs enough history to find the last oil change — and a fuel-heavy
    /// owner can log fifty fill-ups between services. One query serves both rather than two.
    static let historyDepth = 50

    private(set) var recentEntries: [FirestoreEntry] = []
    private(set) var maintenanceDue: [MaintenanceDue] = []
    private(set) var wearItems: [WearItem] = []
    private(set) var upcomingReminders: [Reminder] = []
    private(set) var openRecalls = 0
    private(set) var hasActiveWarranty = false
    private(set) var isLoading = false
    private var reloadToken = 0
    private var lastLoadedKey: LoadKey?
    private(set) var error: AppError?

    init(
        entryService: EntryService = .shared,
        wearService: WearService = .shared,
        reminderService: ReminderService = .shared,
        warrantyService: WarrantyService = .shared,
        revisionStore: VehicleDataRevisionStore = .shared,
        gateEnabled: Bool = VehicleDataRevisionStore.skipGateIsEnabled,
        contentLoader: ((String) async throws -> DashboardContent)? = nil
    ) {
        self.entryService = entryService
        self.wearService = wearService
        self.reminderService = reminderService
        self.warrantyService = warrantyService
        self.revisionStore = revisionStore
        self.gateEnabled = gateEnabled
        self.contentLoader = contentLoader
    }

    func loadDashboard(vehicleId: String) async {
        let currentKey = LoadKey(vehicleId: vehicleId, revision: revisionStore.revision(for: vehicleId))
        // Demo/UI-test runtimes never skip: demo writes bump a different counter, and UI-test
        // journeys mutate then re-check views in-process, so a stale match here would hide them.
        if gateEnabled, lastLoadedKey == currentKey { return }
        reloadToken &+= 1
        let token = reloadToken
        isLoading = true
        defer { if token == reloadToken { isLoading = false } }

        do {
            if let contentLoader {
                let content = try await contentLoader(vehicleId)
                guard token == reloadToken else { return }
                apply(content)
                error = nil
                lastLoadedKey = currentKey
                return
            }
            async let entries = entryService.fetchRecent(vehicleId: vehicleId, limit: Self.historyDepth)
            async let wear = wearService.fetchDashboard(vehicleId: vehicleId)
            async let reminders = reminderService.fetchUpcoming(vehicleId: vehicleId)
            async let warranties = warrantyService.fetchWarranties(vehicleId: vehicleId)
            async let recalls = warrantyService.fetchRecalls(vehicleId: vehicleId)

            let content = DashboardContent(
                entries: try await entries,
                wearItems: try await wear,
                reminders: try await reminders,
                warranties: try await warranties,
                recalls: try await recalls
            )
            guard token == reloadToken else { return }
            apply(content)
            error = nil
            lastLoadedKey = currentKey
        } catch {
            guard token == reloadToken else { return }
            self.error = AppError(from: error)
            lastLoadedKey = nil
        }
    }

    private func apply(_ content: DashboardContent) {
        // The feed shows the newest few; the fetch deliberately reaches further back for the
        // advisor below, so slice rather than widening what the card renders.
        recentEntries = Array(content.entries.prefix(Constants.dashboardRecentLimit))
        maintenanceDue = MaintenanceAdvisor.attentionNeeded(
            entries: content.entries,
            currentOdometer: content.entries.map(\.odometerReading).max(),
            now: .now
        )
        wearItems = content.wearItems
        upcomingReminders = content.reminders
        hasActiveWarranty = content.warranties.contains(where: {
            ($0.expirationDate ?? $0.coverageEnd ?? .distantPast) >= .now
        })
        openRecalls = content.recalls.filter { $0.status == .outstanding }.count
    }
}
