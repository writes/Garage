#if DEBUG
import Foundation
import Observation

/// Debug-only persistence backing the local demo and UI journey tests.
///
/// The store overlays immutable seed data for one process only. Creating a new
/// store intentionally starts from the seeds again, which keeps demo relaunches
/// deterministic without ever sending demo writes to Firebase.
@MainActor
@Observable
final class DemoSessionStore {
    static let shared = DemoSessionStore()

    static let profileFields: ProfileFields = [
        "name": .string("Garage Demo"),
        "address": .string("123 Service Lane"),
        "phone": .string("555-0100"),
        "insuranceCompany": .string("Demo Insurance"),
        "policyNumber": .string("DEMO-0001"),
        "analyticsOptOut": .boolean(true)
    ]

    private var entryOverlay: [String: FirestoreEntry] = [:]
    private var vehicleOverlay: [String: Vehicle] = [:]
    private var reminderOverlay: [String: Reminder] = [:]
    private var partOverlay: [String: SparePart] = [:]
    private var detailingOverlay: [String: DetailingRecord] = [:]
    private var profileOverlay: ProfileFields = [:]
    private(set) var revision = 0

    init() {}

    func save(_ entry: FirestoreEntry) {
        entryOverlay[entry.id] = entry
        revision += 1
    }

    func entries(for vehicleId: String) -> [FirestoreEntry] {
        merged(SeedData.entries(for: vehicleId), with: entryOverlay)
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.entryDate > $1.entryDate }
    }

    func save(_ vehicle: Vehicle) {
        vehicleOverlay[vehicle.id] = vehicle
        revision += 1
    }

    func vehicles() -> [Vehicle] {
        merged(SeedData.vehicles, with: vehicleOverlay)
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    func save(_ reminder: Reminder) {
        reminderOverlay[reminder.id] = reminder
        revision += 1
    }

    func reminders(for vehicleId: String) -> [Reminder] {
        merged(SeedData.reminders(for: vehicleId), with: reminderOverlay)
            .filter { $0.vehicleId == vehicleId }
    }

    func save(_ part: SparePart) {
        partOverlay[part.id] = part
        revision += 1
    }

    func parts(for vehicleId: String) -> [SparePart] {
        merged(SeedData.spareParts(for: vehicleId), with: partOverlay)
            .filter { $0.vehicleId == vehicleId }
    }

    func save(_ record: DetailingRecord) {
        detailingOverlay[record.id] = record
        revision += 1
    }

    func detailingRecords(for vehicleId: String) -> [DetailingRecord] {
        merged(SeedData.detailingRecords(for: vehicleId), with: detailingOverlay)
            .filter { $0.vehicleId == vehicleId }
    }

    func profile() -> ProfileFields {
        Self.profileFields.merging(profileOverlay) { _, overlay in overlay }
    }

    func saveProfile(_ fields: ProfileFields) {
        profileOverlay = fields
        revision += 1
    }

    func saveProfileFields(_ fields: ProfileFields) {
        profileOverlay.merge(fields) { _, replacement in replacement }
        revision += 1
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
#endif
