import Foundation
import Testing
@testable import Garage

struct WearServiceTests {
    @Test func latestDashboardItems_choosesMostRecentSnapshotPerType() {
        let older = WearSnapshot(
            id: "1",
            vehicleId: "vehicle",
            entryId: nil,
            wearItem: .frontTires,
            valuePct: 85,
            valueRaw: "8/32",
            odometerReading: 1000,
            recordedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = WearSnapshot(
            id: "2",
            vehicleId: "vehicle",
            entryId: nil,
            wearItem: .frontTires,
            valuePct: 65,
            valueRaw: "6/32",
            odometerReading: 2000,
            recordedAt: Date(timeIntervalSince1970: 200)
        )

        let items = WearService.latestDashboardItems(from: [older, newer])

        #expect(items.count == 1)
        #expect(items.first?.percentage == 65)
    }

    @Test func latestDashboardItems_dropsTypesWithoutPercentage() {
        let missingPercentage = WearSnapshot(
            id: "missing",
            vehicleId: "vehicle",
            entryId: nil,
            wearItem: .rearTires,
            valuePct: nil,
            valueRaw: "Unknown",
            odometerReading: 1000,
            recordedAt: .now
        )

        let items = WearService.latestDashboardItems(from: [missingPercentage])

        #expect(items.isEmpty)
    }
}
