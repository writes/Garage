import Observation

struct DashboardContent {
    var entries: [FirestoreEntry]
    /// Service history for the maintenance advisor, fetched separately from `entries` and narrowed
    /// to `MaintenanceAdvisor.trackedEntryTypes`. Defaults to empty, which makes the advisor fall
    /// back to `entries` alone — the pre-fix behaviour, and what both the `contentLoader` test seam
    /// and a failed advisor fetch produce.
    var advisorEntries: [FirestoreEntry] = []
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

    /// How far back the recent-entry fetch reaches. The card renders only
    /// `Constants.dashboardRecentLimit` of these; the wider slice is what `hasNoHistory` and the
    /// advisor's odometer baseline read from.
    static let historyDepth = 50

    /// Depth of the advisor's OWN fetch, which is narrowed to the four service types that clear a
    /// maintenance item. One shared type-agnostic query made the advice hostage to fuel-log volume:
    /// an owner logging more than `historyDepth` fill-ups between services pushed every oil change
    /// out of the window, so the advisor reported "never logged" for a car serviced last month.
    /// Fifty entries OF THOSE TYPES is years of service history.
    static let advisorHistoryDepth = 50

    private(set) var recentEntries: [FirestoreEntry] = []
    private(set) var maintenanceDue: [MaintenanceDue] = []
    /// True once a load has completed and found no entries at all. Distinct from `recentEntries
    /// .isEmpty` alone, which is also true before the first load lands — showing the activation CTA
    /// during loading would flash it at owners who have plenty of history.
    private(set) var hasNoHistory = false
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
            async let advisorEntries = advisorHistory(vehicleId: vehicleId)
            async let wear = wearService.fetchDashboard(vehicleId: vehicleId)
            async let reminders = reminderService.fetchUpcoming(vehicleId: vehicleId)
            async let warranties = warrantyService.fetchWarranties(vehicleId: vehicleId)
            async let recalls = warrantyService.fetchRecalls(vehicleId: vehicleId)

            let content = DashboardContent(
                entries: try await entries,
                advisorEntries: await advisorEntries,
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

    /// Non-fatal by design, mirroring ExportViewModel's supplement fetches: this narrowed query is
    /// an improvement on the recent slice, not a prerequisite for it, so a failure degrades the
    /// advice to what `entries` alone supports instead of emptying the whole dashboard.
    ///
    /// `internal` (not `private`): this is the one part of the load that a test can drive
    /// hermetically. `loadDashboard`'s other four fetches go through services with no in-memory
    /// seam (WearService has none at all), so the composed path cannot run without Firebase.
    func advisorHistory(vehicleId: String) async -> [FirestoreEntry] {
        do {
            return try await entryService.fetchEntries(
                query: EntryQuery(vehicleId: vehicleId, entryTypes: MaintenanceAdvisor.trackedEntryTypes),
                limit: Self.advisorHistoryDepth
            )
        } catch {
            AppLogger.entries.error("Advisor service history fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func apply(_ content: DashboardContent) {
        // The feed shows the newest few; the fetch reaches further back so `hasNoHistory` and the
        // odometer baseline are honest, so slice rather than widening what the card renders.
        recentEntries = Array(content.entries.prefix(Constants.dashboardRecentLimit))
        hasNoHistory = content.entries.isEmpty
        // The UNION of both fetches, not the advisor slice alone: `attentionNeeded` stays silent on
        // an empty input, and a vehicle whose only history is fuel must still get its four "never
        // logged" rows. De-duplication keeps a service entry returned by both queries from being
        // counted twice.
        let advisorInput = Self.merged(content.entries, content.advisorEntries)
        maintenanceDue = MaintenanceAdvisor.attentionNeeded(
            entries: advisorInput,
            currentOdometer: advisorInput.map(\.odometerReading).max(),
            now: .now
        )
        wearItems = content.wearItems
        upcomingReminders = content.reminders
        hasActiveWarranty = content.warranties.contains(where: {
            ($0.expirationDate ?? $0.coverageEnd ?? .distantPast) >= .now
        })
        openRecalls = content.recalls.filter { $0.status == .outstanding }.count
    }

    private static func merged(
        _ recent: [FirestoreEntry], _ advisor: [FirestoreEntry]
    ) -> [FirestoreEntry] {
        var seen = Set(recent.map(\.id))
        return recent + advisor.filter { seen.insert($0.id).inserted }
    }
}
