import Foundation
import Testing
@testable import Garage

/// The PDF is the paid artifact and the whole resale pitch, and it was close to a stub: the
/// vehicle block did not identify the car, each service line omitted the mileage it happened at,
/// and five of the sections the export screen offers rendered nothing at all. These tests pin the
/// content, which is the part that is actually the product.
struct DossierContentTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func vehicle(
        nickname: String = "Weekend car",
        vin: String? = nil,
        colour: String? = nil,
        purchaseDate: Date? = nil,
        odometerAtPurchase: Int? = nil
    ) -> Vehicle {
        var vehicle = Vehicle.empty
        vehicle.nickname = nickname
        vehicle.make = "Porsche"
        vehicle.model = "911"
        vehicle.year = 2019
        vehicle.currentOdometer = 42_180
        vehicle.vin = vin
        vehicle.color = colour
        vehicle.purchaseDate = purchaseDate
        vehicle.odometerAtPurchase = odometerAtPurchase
        return vehicle
    }

    private func entry(
        _ type: EntryType = .oilChange,
        odometer: Int = 42_180,
        cost: Double? = nil,
        shop: String? = nil,
        isDiy: Bool? = nil,
        daysAgo: Double = 0
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: UUID().uuidString, vehicleId: "v", userId: "u", entryType: type,
            entryDate: now.addingTimeInterval(-daysAgo * 24 * 60 * 60),
            odometerReading: odometer, cost: cost, isDiy: isDiy, shopName: shop, notes: nil,
            attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }

    private func text(_ lines: [DossierContent.Line]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    // MARK: - Vehicle identity

    /// The old block printed the nickname and odometer only, so the document never said which car
    /// it described — useless to the buyer it exists to convince.
    @Test func theVehicleBlockIdentifiesTheCarNotJustItsNickname() {
        let lines = text(DossierContent.vehicleLines(vehicle()))
        #expect(lines.contains("2019 Porsche 911"))
        #expect(lines.contains("42,180 mi"))
    }

    @Test func theVinIsIncludedWhenKnown() {
        #expect(text(DossierContent.vehicleLines(vehicle(vin: "WP0AB2A99KS123456"))).contains("WP0AB2A99KS123456"))
    }

    /// Absent optional fields are omitted rather than printed as "unknown" — a visible gap is more
    /// honest than a field asserting an absence.
    @Test func absentOptionalFieldsAreOmittedEntirely() {
        let lines = text(DossierContent.vehicleLines(vehicle()))
        #expect(!lines.contains("VIN"))
        #expect(!lines.contains("Colour"))
        #expect(!lines.contains("Owned since"))
    }

    @Test func aNicknameThatRepeatsTheModelIsNotPrintedTwice() {
        let lines = DossierContent.vehicleLines(vehicle(nickname: "911")).map(\.text)
        #expect(lines.filter { $0 == "911" }.isEmpty)
    }

    @Test func purchaseDetailsIncludeTheMileageAtPurchaseWhenBothAreKnown() {
        let subject = vehicle(purchaseDate: now, odometerAtPurchase: 12_000)
        #expect(text(DossierContent.vehicleLines(subject)).contains("12,000 mi"))
    }

    // MARK: - Service lines

    /// The defect that mattered most: mileage at service is the single most important fact in a
    /// maintenance history. "Oil changed at 42,180 mi" is evidence; "oil changed in March" is an
    /// assertion, and the old line printed only the latter.
    @Test func aServiceLineCarriesTheMileageItHappenedAt() {
        #expect(DossierContent.entryLine(entry(odometer: 42_180)).contains("42,180 mi"))
    }

    @Test func aServiceLineCarriesTheCostWhenRecorded() {
        #expect(DossierContent.entryLine(entry(cost: 249.99)).contains("249.99"))
    }

    @Test func aServiceLineNamesTheShopThatDidTheWork() {
        #expect(DossierContent.entryLine(entry(shop: "Hatch Motorsport")).contains("Hatch Motorsport"))
    }

    /// Who did the work is part of the record's credibility, so DIY is stated rather than left
    /// blank — but only when no shop was named.
    @Test func diyIsStatedOnlyWhenNoShopWasNamed() {
        #expect(DossierContent.entryLine(entry(isDiy: true)).contains("DIY"))
        #expect(!DossierContent.entryLine(entry(shop: "Hatch", isDiy: true)).contains("DIY"))
    }

    @Test func aMissingOdometerOrCostIsOmittedRatherThanPrintedAsZero() {
        let line = DossierContent.entryLine(entry(odometer: 0, cost: nil))
        #expect(!line.contains("0 mi"))
        #expect(!line.contains("$0"))
    }

    // MARK: - Grouping

    /// The old export emitted one undifferentiated stream, so finding "every brake service" meant
    /// reading the whole document — the exact task a dossier exists to make easy.
    @Test func historyIsGroupedBySectionAndNewestFirst() {
        let entries = [
            entry(.brake, daysAgo: 100),
            entry(.oilChange, daysAgo: 10),
            entry(.brake, daysAgo: 5),
            entry(.oilChange, daysAgo: 300)
        ]
        let groups = DossierContent.historyGroups(
            entries: entries, selectedSections: [.oilHistory, .brakeHistory]
        )
        #expect(groups.count == 2)
        for group in groups {
            #expect(group.entries.count == 2)
            #expect(group.entries[0].entryDate > group.entries[1].entryDate)
        }
    }

    @Test func anUnselectedSectionIsExcludedEntirely() {
        let entries = [entry(.brake), entry(.oilChange)]
        let groups = DossierContent.historyGroups(entries: entries, selectedSections: [.oilHistory])
        #expect(groups.map(\.section) == [.oilHistory])
    }

    @Test func aSelectedSectionWithNoEntriesProducesNoHeading() {
        let groups = DossierContent.historyGroups(
            entries: [entry(.oilChange)], selectedSections: [.oilHistory, .trackDays]
        )
        #expect(groups.map(\.section) == [.oilHistory])
    }

    /// Every entry type must land in exactly one section, or a saved record silently never appears
    /// in any export.
    @Test func everyEntryTypeMapsToASection() {
        let sections = Set(EntryType.allCases.map(DossierContent.section(for:)))
        #expect(!sections.isEmpty)
        for type in EntryType.allCases {
            #expect(ReportSection.allCases.contains(DossierContent.section(for: type)))
        }
    }

    // MARK: - Summaries that used to render nothing

    @Test func theCostSummaryReportsTotalAndPerMile() {
        let entries = [
            entry(odometer: 30_000, cost: 500, daysAgo: 400),
            entry(odometer: 40_000, cost: 500, daysAgo: 10)
        ]
        let lines = text(DossierContent.costSummaryLines(entries: entries, now: now))
        #expect(lines.contains("1,000") || lines.contains("1000"))
        #expect(lines.contains("/mi"))
        #expect(lines.contains("2 recorded entries"))
    }

    @Test func theCostSummaryIsAbsentRatherThanZeroWhenNothingHasACost() {
        #expect(DossierContent.costSummaryLines(entries: [entry()], now: now).isEmpty)
    }

    @Test func theWearSummaryListsEachItemWithItsRemainingLife() {
        let items = [
            WearItem(type: .frontBrakePads, percentage: 45, rawValue: "45%", milesToReplacement: nil)
        ]
        let lines = text(DossierContent.wearSummaryLines(items))
        #expect(lines.contains("Front Brake Pads"))
        #expect(lines.contains("45%"))
    }

    @Test func emptySummariesProduceNoHeading() {
        #expect(DossierContent.wearSummaryLines([]).isEmpty)
        #expect(DossierContent.warrantyLines([], now: now).isEmpty)
        #expect(DossierContent.recallLines([]).isEmpty)
    }

    /// Active-versus-expired is the fact a buyer is looking for, so it is stated outright rather
    /// than left to be worked out from a date.
    @Test func warrantyLinesStateWhetherCoverageIsStillActive() {
        var active = Warranty(
            id: "1", vehicleId: "v", warrantyType: .extended,
            startDate: now.addingTimeInterval(-86_400)
        )
        active.expirationDate = now.addingTimeInterval(86_400)
        active.providerName = "Zurich"
        #expect(text(DossierContent.warrantyLines([active], now: now)).contains("active until"))

        var expired = active
        expired.expirationDate = now.addingTimeInterval(-86_400)
        #expect(text(DossierContent.warrantyLines([expired], now: now)).contains("expired"))
    }

    @Test func recallLinesCarryTheirStatus() {
        let recall = Recall(
            id: "1", vehicleId: "v", campaignNumber: "24V-123", title: "Fuel pump",
            status: .outstanding, recallSource: .manual
        )
        let lines = text(DossierContent.recallLines([recall]))
        #expect(lines.contains("Fuel pump"))
        #expect(lines.contains("24V-123"))
        #expect(lines.lowercased().contains("outstanding"))
    }
}
