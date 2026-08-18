import Foundation
import Testing
@testable import Garage

@MainActor
struct DesignStructureTests {
    @Test func controlNormalizesDroppedTabsToTheFirstVisibleTab() {
        let structure = DesignPack.control.structure
        #expect(structure.normalizedTab(.stats) == .stats)
        #expect(structure.normalizedTab(.handover) == .dashboard)
    }

    @Test func variantANormalizesStatsAndSettingsToHood() {
        let structure = DesignPack.variantA.structure
        #expect(structure.normalizedTab(.stats) == .dashboard)
        #expect(structure.normalizedTab(.settings) == .dashboard)
        #expect(structure.normalizedTab(.handover) == .handover)
    }

    @Test func systemsBayDeriverMapsMaintenanceStatusToTileSeverity() {
        let overdue = MaintenanceDue(
            item: .oilAndFilter,
            status: .overdue,
            milesPastDue: 430,
            dueDate: nil,
            lastServicedAt: Date()
        )
        let tiles = SystemsBayDeriver.tiles(from: [overdue])
        #expect(tiles.count == 1)
        #expect(tiles[0].status == SystemsBayTile.Status.bad)
        #expect(tiles[0].dueText.contains("430"))
    }
}
