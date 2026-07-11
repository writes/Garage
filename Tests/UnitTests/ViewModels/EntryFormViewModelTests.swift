import Testing
@testable import Garage

@MainActor
struct EntryFormViewModelTests {
    @Test func odometerValidation_rejectsLowerThanLast() {
        let viewModel = EntryFormViewModel()
        viewModel.lastKnownOdometer = 50_000
        viewModel.odometerReading = "49000"

        let result = viewModel.validateOdometer()

        #expect(result == false)
        #expect(viewModel.error == .validation("Odometer must be at least 50,000."))
    }

    @Test func odometerValidation_acceptsHigherThanLast() {
        let viewModel = EntryFormViewModel()
        viewModel.lastKnownOdometer = 50_000
        viewModel.odometerReading = "50150"

        let result = viewModel.validateOdometer()

        #expect(result == true)
    }

    @Test func save_encodesFuelDetailsAndPushesOdometerToVehicle() async throws {
        let vehicle = testVehicle()
        let entryService = EntryService(testEntries: [])
        let vehicleService = VehicleService(
            testVehicles: [vehicle],
            purchaseService: PurchaseService(testIsPro: false)
        )
        let viewModel = EntryFormViewModel(
            entryService: entryService,
            vehicleService: vehicleService,
            userID: { "user" }
        )
        viewModel.odometerReading = "12100"
        viewModel.cost = "65.25"

        let saved = await viewModel.save(
            vehicle: vehicle,
            entryType: .fuel,
            details: FuelEntry(
                gallons: 12.5,
                pricePerGallon: 5.22,
                totalCost: 65.25,
                stationName: "Garage Fuel",
                fuelGrade: .premium91,
                calculatedMPG: 20.1
            )
        )
        let entries = try await entryService.fetchRecent(vehicleId: vehicle.id)
        let vehicles = try await vehicleService.fetchVehicles()

        #expect(saved)
        #expect(entries.count == 1)
        #expect(entries.first?.details["gallons"] == AnyCodable(12.5))
        #expect(entries.first?.details["fuelGrade"] == AnyCodable("premium_91"))
        #expect(vehicles.first?.currentOdometer == 12_100)
    }

    @Test func save_encodesOilChangeDetails() async throws {
        let vehicle = testVehicle()
        let entryService = EntryService(testEntries: [])
        let viewModel = EntryFormViewModel(
            entryService: entryService,
            vehicleService: VehicleService(
                testVehicles: [vehicle],
                purchaseService: PurchaseService(testIsPro: false)
            ),
            userID: { "user" }
        )
        viewModel.odometerReading = "12000"

        let saved = await viewModel.save(
            vehicle: vehicle,
            entryType: .oilChange,
            details: OilChangeEntry(
                oilBrand: "Mobil 1",
                oilGrade: "0W-40",
                quantityQuarts: 8.5,
                filterBrand: "Mann"
            )
        )
        let entries = try await entryService.fetchRecent(vehicleId: vehicle.id)

        #expect(saved)
        #expect(entries.first?.details["oilBrand"] == AnyCodable("Mobil 1"))
        #expect(entries.first?.details["quantityQuarts"] == AnyCodable(8.5))
    }

    @Test func firstEntrySave_emitsTypedEventWithSchemaVersion() async {
        let vehicle = testVehicle()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = EntryFormViewModel(
            entryService: EntryService(testEntries: []),
            vehicleService: VehicleService(
                testVehicles: [vehicle],
                purchaseService: PurchaseService(testIsPro: false)
            ),
            analytics: analytics,
            userID: { "user" }
        )
        viewModel.odometerReading = "12100"

        let didSave = await viewModel.save(
            vehicle: vehicle,
            entryType: .fuel,
            details: FuelEntry(
                gallons: 12.5,
                pricePerGallon: 5.22,
                totalCost: 65.25,
                stationName: "Garage Fuel",
                fuelGrade: .premium91,
                calculatedMPG: 20.1
            )
        )

        #expect(didSave)
        #expect(analytics.events == [.firstEntryAdded(entryType: .fuel)])
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "first_entry_added", parameters: [.entryType(.fuel)])
        ])
    }

    @Test func firstEntrySave_doesNotDuplicateAcrossVehiclesInTheSameAccount() async {
        let firstVehicle = testVehicle()
        var secondVehicle = firstVehicle
        secondVehicle.id = "vehicle-b"
        secondVehicle.nickname = "Second car"
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = EntryFormViewModel(
            entryService: EntryService(testEntries: [existingEntry(for: firstVehicle)]),
            vehicleService: VehicleService(
                testVehicles: [firstVehicle, secondVehicle],
                purchaseService: PurchaseService(testIsPro: false)
            ),
            analytics: analytics,
            userID: { "user" }
        )
        viewModel.odometerReading = "12100"

        let didSave = await viewModel.save(
            vehicle: secondVehicle,
            entryType: .maintenance,
            details: maintenanceDetails()
        )

        #expect(didSave)
        #expect(analytics.events.isEmpty)
    }

    @Test func optOut_dropsFirstEntryEventAfterSuccessfulSave() async {
        let vehicle = testVehicle()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(false)
        let viewModel = EntryFormViewModel(
            entryService: EntryService(testEntries: []),
            vehicleService: VehicleService(
                testVehicles: [vehicle],
                purchaseService: PurchaseService(testIsPro: false)
            ),
            analytics: analytics,
            userID: { "user" }
        )
        viewModel.odometerReading = "12100"

        let didSave = await viewModel.save(
            vehicle: vehicle,
            entryType: .maintenance,
            details: MaintenanceEntry(
                item: .airFilter,
                otherLabel: nil,
                nextDueMileage: nil,
                nextDueDate: nil,
                symptomDescription: nil,
                resolutionDescription: nil,
                status: .resolved
            )
        )

        #expect(didSave)
        #expect(analytics.events.isEmpty)
        #expect(analytics.enabledValues.contains(false))
    }

    private func testVehicle() -> Vehicle {
        Vehicle(
            id: "vehicle",
            userId: "user",
            nickname: "Test car",
            make: "Garage",
            model: "Test",
            year: 2026,
            currentOdometer: 10_000
        )
    }

    private func existingEntry(for vehicle: Vehicle) -> FirestoreEntry {
        FirestoreEntry(
            id: "existing-entry", vehicleId: vehicle.id, userId: "user", entryType: .maintenance,
            entryDate: .now, odometerReading: 10_100, cost: nil, isDiy: nil, shopName: nil,
            notes: nil, attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }

    private func maintenanceDetails() -> MaintenanceEntry {
        MaintenanceEntry(
            item: .airFilter, otherLabel: nil, nextDueMileage: nil, nextDueDate: nil,
            symptomDescription: nil, resolutionDescription: nil, status: .resolved
        )
    }
}
