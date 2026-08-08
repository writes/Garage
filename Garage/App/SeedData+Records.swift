import Foundation

extension SeedData {
    static func entries(for vehicleId: String) -> [FirestoreEntry] {
        entries
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.entryDate > $1.entryDate }
    }

    static func wearSnapshots(for vehicleId: String) -> [WearSnapshot] {
        wearSnapshots.filter { $0.vehicleId == vehicleId }
    }

    static func reminders(for vehicleId: String) -> [Reminder] {
        reminders.filter { $0.vehicleId == vehicleId }
    }

    static func spareParts(for vehicleId: String) -> [SparePart] {
        spareParts.filter { $0.vehicleId == vehicleId }
    }

    static func detailingRecords(for vehicleId: String) -> [DetailingRecord] {
        detailingRecords.filter { $0.vehicleId == vehicleId }
    }

    private static let entries: [FirestoreEntry] = [
        FirestoreEntry(
            id: "seed-viper-track",
            vehicleId: "seed-viper",
            userId: AppRuntime.demoUserId,
            entryType: .trackDay,
            entryDate: daysAgo(6),
            odometerReading: 18_240,
            cost: 425,
            isDiy: nil,
            shopName: "Willow Springs",
            notes: "HPDE shakedown. Car felt stable under braking; front tires picked up one heat cycle.",
            attachmentPaths: [],
            isResolved: nil,
            details: detailsMap(TrackDayEntry(
                venueName: "Willow Springs", eventType: .hpde, bestLapTime: "1:34.821",
                conditions: .dry, heatCyclesAdded: 1
            )),
            createdAt: daysAgo(6),
            updatedAt: daysAgo(6)
        ),
        FirestoreEntry(
            id: "seed-viper-oil",
            vehicleId: "seed-viper",
            userId: AppRuntime.demoUserId,
            entryType: .oilChange,
            entryDate: daysAgo(15),
            odometerReading: 18_120,
            cost: 165,
            isDiy: true,
            shopName: nil,
            notes: "Pre-event oil service with Mobil 1 0W-40 and SRT filter.",
            attachmentPaths: [],
            isResolved: nil,
            details: detailsMap(OilChangeEntry(
                oilBrand: "Mobil 1", oilGrade: "0W-40", quantityQuarts: 10.5, filterBrand: "Mopar SRT"
            )),
            createdAt: daysAgo(15),
            updatedAt: daysAgo(15)
        ),
        FirestoreEntry(
            id: "seed-viper-brake",
            vehicleId: "seed-viper",
            userId: AppRuntime.demoUserId,
            entryType: .brake,
            entryDate: daysAgo(28),
            odometerReading: 17_980,
            cost: 390,
            isDiy: true,
            shopName: nil,
            notes: "Installed track pads and flushed with high-temp fluid.",
            attachmentPaths: [],
            isResolved: nil,
            details: detailsMap(BrakeEntry(
                action: .padsReplaced, position: .all, padBrand: "G-LOC", padCompound: "R12/R10",
                fluidFlushed: true
            )),
            createdAt: daysAgo(28),
            updatedAt: daysAgo(28)
        ),
        FirestoreEntry(
            id: "seed-sq5-fuel",
            vehicleId: "seed-sq5",
            userId: AppRuntime.demoUserId,
            entryType: .fuel,
            entryDate: daysAgo(3),
            odometerReading: 82_440,
            cost: 74.22,
            isDiy: nil,
            shopName: "Chevron",
            notes: "Premium 91 fill-up.",
            attachmentPaths: [],
            isResolved: nil,
            details: detailsMap(FuelEntry(
                gallons: 18.4, pricePerGallon: 4.03, totalCost: 74.15, fuelGrade: .premium91,
                calculatedMPG: 19.6
            )),
            createdAt: daysAgo(3),
            updatedAt: daysAgo(3)
        )
    ]

    private static let wearSnapshots: [WearSnapshot] = [
        WearSnapshot(
            id: "seed-wear-front-pads",
            vehicleId: "seed-viper",
            entryId: "seed-viper-brake",
            wearItem: .frontBrakePads,
            valuePct: 82,
            valueRaw: "10.5 mm",
            odometerReading: 18_240,
            recordedAt: daysAgo(6),
            createdAt: daysAgo(6)
        ),
        WearSnapshot(
            id: "seed-wear-rear-pads",
            vehicleId: "seed-viper",
            entryId: "seed-viper-brake",
            wearItem: .rearBrakePads,
            valuePct: 76,
            valueRaw: "9.8 mm",
            odometerReading: 18_240,
            recordedAt: daysAgo(6),
            createdAt: daysAgo(6)
        ),
        WearSnapshot(
            id: "seed-wear-front-tires",
            vehicleId: "seed-viper",
            entryId: "seed-viper-track",
            wearItem: .frontTires,
            valuePct: 58,
            valueRaw: "5/32 in, 8 heat cycles",
            odometerReading: 18_240,
            recordedAt: daysAgo(6),
            createdAt: daysAgo(6)
        ),
        WearSnapshot(
            id: "seed-wear-rear-tires",
            vehicleId: "seed-viper",
            entryId: "seed-viper-track",
            wearItem: .rearTires,
            valuePct: 61,
            valueRaw: "6/32 in, 8 heat cycles",
            odometerReading: 18_240,
            recordedAt: daysAgo(6),
            createdAt: daysAgo(6)
        )
    ]

    private static let reminders: [Reminder] = [
        Reminder(
            id: "seed-reminder-oil",
            vehicleId: "seed-viper",
            title: "Oil change",
            entryType: .oilChange,
            dueDate: daysFromNow(75),
            dueMileage: 20_620,
            repeatIntervalMonths: 6,
            repeatIntervalMiles: 2_500,
            notes: "Track-use interval",
            isProFeature: false,
            createdAt: daysAgo(15)
        ),
        Reminder(
            id: "seed-reminder-brake-fluid",
            vehicleId: "seed-viper",
            title: "Brake fluid inspection",
            entryType: .brake,
            dueDate: daysFromNow(35),
            dueMileage: nil,
            repeatIntervalMonths: 3,
            repeatIntervalMiles: nil,
            notes: "Check before next event",
            isProFeature: false,
            createdAt: daysAgo(28)
        )
    ]

    private static let spareParts: [SparePart] = [
        SparePart(
            id: "seed-part-brake-fluid",
            vehicleId: "seed-viper",
            name: "Racing brake fluid",
            category: .brakes,
            brand: "Castrol",
            partNumber: nil,
            quantity: 2,
            unitCost: 78,
            wherePurchased: "Track supplier",
            purchaseDate: daysAgo(20),
            storageLocation: "Garage shelf B",
            condition: .new,
            photoStoragePath: nil,
            receiptStoragePath: nil,
            isConsumed: false,
            consumedAtEntryId: nil,
            notes: "Keep for next pre-event flush."
        )
    ]

    private static let detailingRecords: [DetailingRecord] = [
        DetailingRecord(
            id: "seed-detailing-viper",
            vehicleId: "seed-viper",
            serviceDate: daysAgo(40),
            serviceType: .paintCorrection,
            title: "Light polish and sealant",
            providerName: "DIY",
            productName: "Jescar Power Lock",
            correctionType: "Light polish",
            coverageArea: nil,
            layers: nil,
            warrantyExpiration: nil,
            maintenanceScheduleNotes: nil,
            cost: 42,
            notes: "Cleaned up light tow-hook-area marring.",
            attachmentPaths: []
        )
    ]

    /// Encodes seed `details` through the exact path the entry forms use at save time
    /// (`EntryFormViewModel.makeAnyCodableMap`), so demo data cannot drift from the struct
    /// `decodedDetails(as:)` reads it back into — hand-written maps silently cost the Stats venue,
    /// the MPG chart and every edit prefill. The throw is unreachable for these literal structs.
    private static func detailsMap<T: Encodable>(_ details: T) -> [String: AnyCodable] {
        do {
            return try EntryFormViewModel.makeAnyCodableMap(from: details)
        } catch {
            preconditionFailure("Seed details for \(T.self) are not encodable: \(error)")
        }
    }

    private static func daysAgo(_ days: Double) -> Date {
        Date(timeIntervalSinceNow: -86_400 * days)
    }

    private static func daysFromNow(_ days: Double) -> Date {
        Date(timeIntervalSinceNow: 86_400 * days)
    }
}
