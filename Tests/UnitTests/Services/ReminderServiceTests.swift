import Foundation
import Testing
@testable import Garage

struct ReminderServiceTests {
    @Test func sortUpcoming_ordersByDateAscending() {
        let later = Reminder(id: "2", vehicleId: "vehicle", title: "Later", dueDate: Date(timeIntervalSince1970: 200))
        let sooner = Reminder(id: "1", vehicleId: "vehicle", title: "Sooner", dueDate: Date(timeIntervalSince1970: 100))

        let sorted = ReminderService.sortUpcoming([later, sooner])

        #expect(sorted.map(\.id) == ["1", "2"])
    }
}
