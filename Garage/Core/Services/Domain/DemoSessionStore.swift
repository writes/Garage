import Foundation

/// Debug-only persistence backing the local demo and UI journey tests.
///
/// The store overlays immutable seed data for one process only. Creating a new
/// store intentionally starts from the seeds again, which keeps demo relaunches
/// deterministic without ever sending demo writes to Firebase.
@MainActor
final class DemoSessionStore {
    static let shared = DemoSessionStore()

    static let profileFields = [
        "name": "Garage Demo",
        "address": "123 Service Lane",
        "phone": "555-0100",
        "insuranceCompany": "Demo Insurance",
        "policyNumber": "DEMO-0001"
    ]

    private var entryOverlay: [String: FirestoreEntry] = [:]
    private var vehicleOverlay: [String: Vehicle] = [:]
    private var reminderOverlay: [String: Reminder] = [:]
    private var partOverlay: [String: SparePart] = [:]
    private var detailingOverlay: [String: DetailingRecord] = [:]
    private var profileOverlay: [String: String] = [:]

    init() {}

    func save(_ entry: FirestoreEntry) {
        entryOverlay[entry.id] = entry
    }

    func entries(for vehicleId: String) -> [FirestoreEntry] {
        merged(SeedData.entries(for: vehicleId), with: entryOverlay)
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.entryDate > $1.entryDate }
    }

    func save(_ vehicle: Vehicle) {
        vehicleOverlay[vehicle.id] = vehicle
    }

    func vehicles() -> [Vehicle] {
        merged(SeedData.vehicles, with: vehicleOverlay)
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    func save(_ reminder: Reminder) {
        reminderOverlay[reminder.id] = reminder
    }

    func reminders(for vehicleId: String) -> [Reminder] {
        merged(SeedData.reminders(for: vehicleId), with: reminderOverlay)
            .filter { $0.vehicleId == vehicleId }
    }

    func save(_ part: SparePart) {
        partOverlay[part.id] = part
    }

    func parts(for vehicleId: String) -> [SparePart] {
        merged(SeedData.spareParts(for: vehicleId), with: partOverlay)
            .filter { $0.vehicleId == vehicleId }
    }

    func save(_ record: DetailingRecord) {
        detailingOverlay[record.id] = record
    }

    func detailingRecords(for vehicleId: String) -> [DetailingRecord] {
        merged(SeedData.detailingRecords(for: vehicleId), with: detailingOverlay)
            .filter { $0.vehicleId == vehicleId }
    }

    func profile() -> [String: String] {
        Self.profileFields.merging(profileOverlay) { _, overlay in overlay }
    }

    func saveProfile(_ fields: [String: String]) {
        profileOverlay = fields
    }

    private func merged<Value: Identifiable>(
        _ seed: [Value],
        with overlay: [String: Value]
    ) -> [Value] where Value.ID == String {
        Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
            .merging(overlay) { _, overlay in overlay }
            .values
            .map { $0 }
    }
}
