import Foundation
import Testing
@testable import Garage

@MainActor
struct DemoSessionStoreTests {
    @Test func sessionWrites_overlaySeedsAndAreVisibleImmediately() {
        let store = DemoSessionStore()
        let vehicle = testVehicle(id: "session-vehicle")
        let entry = testEntry(id: "session-entry", vehicleId: vehicle.id)
        let reminder = Reminder(id: "session-reminder", vehicleId: vehicle.id, title: "Rotate tires")
        let part = SparePart(
            id: "session-part",
            vehicleId: vehicle.id,
            name: "Track pads",
            category: .brakes,
            quantity: 1,
            condition: .new,
            isConsumed: false
        )
        let record = DetailingRecord(
            id: "session-detailing",
            vehicleId: vehicle.id,
            serviceDate: .now,
            serviceType: .wash,
            title: "Hand wash",
            attachmentPaths: []
        )

        store.save(vehicle)
        store.save(entry)
        store.save(reminder)
        store.save(part)
        store.save(record)
        store.saveProfile(["name": .string("Session Driver")])

        #expect(store.vehicles().contains(vehicle))
        #expect(store.entries(for: vehicle.id).contains(entry))
        #expect(store.reminders(for: vehicle.id).contains(reminder))
        #expect(store.parts(for: vehicle.id).contains(part))
        #expect(store.detailingRecords(for: vehicle.id).contains(record))
        #expect(store.profile()["name"] == .string("Session Driver"))
        #expect(store.profile()["phone"] == DemoSessionStore.profileFields["phone"])
    }

    @Test func deleteEntry_removesAnOverlaySaveAndBumpsRevision() {
        let store = DemoSessionStore()
        let vehicle = testVehicle(id: "delete-vehicle")
        let entry = testEntry(id: "delete-entry", vehicleId: vehicle.id)
        store.save(entry)
        let revisionBeforeDelete = store.revision

        store.deleteEntry(id: entry.id)

        #expect(!store.entries(for: vehicle.id).contains(where: { $0.id == entry.id }))
        #expect(store.revision > revisionBeforeDelete)
    }

    @Test func deleteReminder_removesAnOverlaySaveAndBumpsRevision() {
        let store = DemoSessionStore()
        let reminder = Reminder(id: "delete-reminder", vehicleId: "delete-vehicle", title: "Rotate tires")
        store.save(reminder)
        let revisionBeforeDelete = store.revision

        store.deleteReminder(id: reminder.id)

        #expect(!store.reminders(for: reminder.vehicleId).contains(where: { $0.id == reminder.id }))
        #expect(store.revision > revisionBeforeDelete)
    }

    @Test func freshStore_resetsSessionWritesAndKeepsOnlySeeds() {
        let firstLaunch = DemoSessionStore()
        let vehicle = testVehicle(id: "relaunch-vehicle")
        firstLaunch.save(vehicle)
        firstLaunch.save(testEntry(id: "relaunch-entry", vehicleId: vehicle.id))
        firstLaunch.saveProfile(["name": .string("Changed in prior launch")])

        let relaunchedStore = DemoSessionStore()

        #expect(!relaunchedStore.vehicles().contains(where: { $0.id == vehicle.id }))
        #expect(relaunchedStore.entries(for: vehicle.id).isEmpty)
        #expect(relaunchedStore.profile()["name"] == DemoSessionStore.profileFields["name"])
    }

    private func testVehicle(id: String) -> Vehicle {
        Vehicle(
            id: id,
            userId: AppRuntime.demoUserId,
            nickname: "Session Car",
            make: "Garage",
            model: "Demo",
            year: 2026,
            currentOdometer: 100,
            displayOrder: 99
        )
    }

    private func testEntry(id: String, vehicleId: String) -> FirestoreEntry {
        FirestoreEntry(
            id: id,
            vehicleId: vehicleId,
            userId: AppRuntime.demoUserId,
            entryType: .maintenance,
            entryDate: .now,
            odometerReading: 100,
            cost: nil,
            isDiy: true,
            shopName: nil,
            notes: "Visible during this launch",
            attachmentPaths: [],
            isResolved: nil,
            details: [:],
            createdAt: .now,
            updatedAt: .now
        )
    }
}
