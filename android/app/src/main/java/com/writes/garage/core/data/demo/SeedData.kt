package com.writes.garage.core.data.demo

import com.writes.garage.core.domain.Constants
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.FuelType
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallSource
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.Vehicle
import java.time.Duration
import java.time.Instant

/**
 * Demo-mode sample data (port of iOS `SeedData*.swift`, expanded to cover every entry type).
 * Everything is relative to [now] so the demo always looks fresh and tests are deterministic.
 */
class SeedData(private val now: Instant = Instant.now()) {
    val userId: String = Constants.DEMO_USER_ID

    val vehicles: List<Vehicle> = listOf(
        Vehicle(
            id = VIPER_ID, userId = userId, nickname = "Viper ACR", make = "Dodge", model = "Viper ACR",
            year = 2008, currentOdometer = 18_240, fuelType = FuelType.PREMIUM_93, color = "Red",
            engineOilType = "Mobil 1 0W-40", tireSizeFront = "295/30R18", tireSizeRear = "345/30R19",
            displayOrder = 0, createdAt = daysAgo(400),
        ),
        Vehicle(
            id = SQ5_ID, userId = userId, nickname = "Daily SQ5", make = "Audi", model = "SQ5",
            year = 2015, currentOdometer = 82_440, fuelType = FuelType.PREMIUM_91, color = "Gray",
            engineOilType = "Liqui Moly 5W-40", tireSizeFront = "255/45R20", tireSizeRear = "255/45R20",
            displayOrder = 1, createdAt = daysAgo(380),
        ),
    )

    val entries: List<Entry> = listOf(
        // --- Viper ACR ---
        entry("seed-viper-track", VIPER_ID, EntryType.TRACK_DAY, 6, 18_240, 425.0, shop = "Willow Springs",
            notes = "HPDE shakedown. Car felt stable under braking; front tires picked up one heat cycle.",
            details = mapOf("venueName" to "Willow Springs", "eventType" to "hpde", "bestLapTime" to "1:34.821",
                "conditions" to "dry", "heatCyclesAdded" to 1, "numberOfLaps" to 24)),
        entry("seed-viper-oil", VIPER_ID, EntryType.OIL_CHANGE, 15, 18_120, 165.0, diy = true,
            notes = "Pre-event oil service with Mobil 1 0W-40 and SRT filter.",
            details = mapOf("oilBrand" to "Mobil 1", "oilGrade" to "0W-40", "quantityQuarts" to 10.5,
                "filterBrand" to "Mopar SRT")),
        entry("seed-viper-brake", VIPER_ID, EntryType.BRAKE, 28, 17_980, 390.0, diy = true,
            notes = "Installed track pads and flushed with high-temp fluid.",
            details = mapOf("action" to "pads_replaced", "position" to "all", "padBrand" to "G-LOC",
                "padCompound" to "R12/R10", "fluidFlushed" to true)),
        entry("seed-viper-tire", VIPER_ID, EntryType.TIRE, 34, 17_900, 1_980.0, shop = "Tire Rack Pit Crew",
            notes = "Fresh Michelin Pilot Sport Cup 2 set.",
            details = mapOf("actionType" to "new_install", "tireBrand" to "Michelin", "tireModel" to "Pilot Sport Cup 2",
                "position" to "all_four", "tireSizeFront" to "295/30R18", "tireSizeRear" to "345/30R19",
                "heatCycles" to 0)),
        entry("seed-viper-align", VIPER_ID, EntryType.ALIGNMENT, 33, 17_910, 220.0, shop = "Apex Alignment",
            notes = "Track alignment, -3.0 front camber.",
            details = mapOf("frontLeftCamber" to "-3.0", "frontRightCamber" to "-3.0", "frontLeftToe" to "0.05",
                "frontRightToe" to "0.05")),
        entry("seed-viper-upgrade", VIPER_ID, EntryType.UPGRADE, 70, 17_400, 2_150.0, shop = "Fox Motorsport",
            notes = "Adjustable coilover package.",
            details = mapOf("title" to "Coilover kit", "brand" to "Ohlins", "partNumber" to "DOU-MI01",
                "category" to "suspension")),
        entry("seed-viper-oilan", VIPER_ID, EntryType.OIL_ANALYSIS, 14, 18_130, 38.0,
            notes = "Looks healthy. Copper trending low.",
            details = mapOf("labName" to "Blackstone Labs", "iron" to 12.0, "aluminum" to 4.0, "copper" to 6.0,
                "viscosity" to "14.2 cSt", "milesOnOil" to 1_200, "labRecommendation" to "Change at normal interval.")),
        entry("seed-viper-consume", VIPER_ID, EntryType.OIL_CONSUMPTION, 9, 18_190, 12.0, diy = true,
            notes = "Topped off after track weekend.",
            details = mapOf("amountAddedQuarts" to 0.5, "runningTotalSinceLastChange" to 0.5,
                "oilBrand" to "Mobil 1", "oilGrade" to "0W-40")),
        entry("seed-viper-fuel", VIPER_ID, EntryType.FUEL, 7, 18_230, 96.4, shop = "Shell V-Power",
            details = mapOf("gallons" to 20.1, "pricePerGallon" to 4.80, "totalCost" to 96.48,
                "fuelGrade" to "premium_93", "stationName" to "Shell")),
        // --- Daily SQ5 ---
        entry("seed-sq5-fuel", SQ5_ID, EntryType.FUEL, 3, 82_440, 74.22, shop = "Chevron",
            notes = "Premium 91 fill-up.",
            details = mapOf("gallons" to 18.4, "pricePerGallon" to 4.03, "totalCost" to 74.15,
                "fuelGrade" to "premium_91", "calculatedMPG" to 19.6)),
        entry("seed-sq5-fuel2", SQ5_ID, EntryType.FUEL, 12, 82_080, 71.80, shop = "Costco",
            details = mapOf("gallons" to 18.0, "pricePerGallon" to 3.99, "totalCost" to 71.82,
                "fuelGrade" to "premium_91", "calculatedMPG" to 20.1)),
        entry("seed-sq5-fuel3", SQ5_ID, EntryType.FUEL, 21, 81_710, 76.50, shop = "Shell",
            details = mapOf("gallons" to 18.7, "pricePerGallon" to 4.09, "totalCost" to 76.48,
                "fuelGrade" to "premium_91", "calculatedMPG" to 18.8)),
        entry("seed-sq5-fuel4", SQ5_ID, EntryType.FUEL, 30, 81_360, 72.10, shop = "Chevron",
            details = mapOf("gallons" to 17.9, "pricePerGallon" to 4.03, "totalCost" to 72.14,
                "fuelGrade" to "premium_91", "calculatedMPG" to 19.3)),
        entry("seed-sq5-oil", SQ5_ID, EntryType.OIL_CHANGE, 45, 81_900, 129.0, shop = "Audi Service",
            details = mapOf("oilBrand" to "Liqui Moly", "oilGrade" to "5W-40", "quantityQuarts" to 7.0,
                "filterBrand" to "Mann")),
        entry("seed-sq5-maint", SQ5_ID, EntryType.MAINTENANCE, 60, 81_300, 240.0, shop = "Independent Euro Shop",
            notes = "Cabin and engine air filters, wiper blades.",
            details = mapOf("item" to "air_filter", "status" to "completed", "nextDueMileage" to 96_000)),
        entry("seed-sq5-repair", SQ5_ID, EntryType.REPAIR, 95, 80_200, 1_150.0, shop = "Independent Euro Shop",
            notes = "Replaced leaking water pump and thermostat.", isResolved = true,
            details = mapOf("title" to "Water pump + thermostat", "symptomDescription" to "Coolant smell, low level",
                "resolutionDescription" to "Replaced pump and thermostat housing", "status" to "completed",
                "replacedParts" to listOf("Water pump", "Thermostat"))),
        entry("seed-sq5-tire", SQ5_ID, EntryType.TIRE, 110, 79_500, 4.0, diy = true,
            notes = "Tread depth check before winter.",
            details = mapOf("actionType" to "tread_depth_reading", "tireBrand" to "Continental",
                "tireModel" to "ExtremeContact DWS06", "position" to "all_four", "treadDepthFL" to "6/32",
                "treadDepthFR" to "6/32", "treadDepthRL" to "7/32", "treadDepthRR" to "7/32")),
        entry("seed-sq5-brake", SQ5_ID, EntryType.BRAKE, 150, 78_000, 520.0, shop = "Audi Service",
            notes = "Front pads and rotors.",
            details = mapOf("action" to "pads_and_rotors", "position" to "front", "padBrand" to "OEM",
                "fluidFlushed" to false)),
        entry("seed-sq5-align", SQ5_ID, EntryType.ALIGNMENT, 150, 78_010, 129.0, shop = "Discount Tire",
            details = mapOf("shopNotes" to "All within spec")),
        entry("seed-sq5-dme", SQ5_ID, EntryType.DME_REPORT, 200, 76_500, 0.0,
            notes = "Pre-purchase-style scan, no stored faults.",
            details = mapOf("providerName" to "Independent Euro Shop", "reportType" to "fault_codes",
                "summary" to "No stored fault codes.")),
    )

    val reminders: List<Reminder> = listOf(
        Reminder("seed-reminder-oil", VIPER_ID, "Oil change", EntryType.OIL_CHANGE, dueDate = daysFromNow(75),
            dueMileage = 20_620, repeatIntervalMonths = 6, repeatIntervalMiles = 2_500,
            notes = "Track-use interval", createdAt = daysAgo(15)),
        Reminder("seed-reminder-brake-fluid", VIPER_ID, "Brake fluid inspection", EntryType.BRAKE,
            dueDate = daysFromNow(35), repeatIntervalMonths = 3, notes = "Check before next event",
            createdAt = daysAgo(28)),
        Reminder("seed-reminder-sq5-oil", SQ5_ID, "Oil change", EntryType.OIL_CHANGE, dueDate = daysFromNow(120),
            dueMileage = 91_900, repeatIntervalMonths = 12, repeatIntervalMiles = 10_000, createdAt = daysAgo(45)),
        Reminder("seed-reminder-sq5-tires", SQ5_ID, "Rotate tires", EntryType.TIRE, dueDate = daysFromNow(-5),
            dueMileage = 85_000, repeatIntervalMiles = 6_000, notes = "Overdue", createdAt = daysAgo(110)),
        Reminder("seed-reminder-sq5-done", SQ5_ID, "Cabin filter", EntryType.MAINTENANCE, dueDate = daysAgo(55),
            createdAt = daysAgo(120), completedAt = daysAgo(60)),
    )

    val recalls: List<Recall> = listOf(
        Recall("seed-recall-sq5-1", SQ5_ID, campaignNumber = "15V-123", title = "Fuel pump relay may fail",
            description = "Demo recall. The fuel pump relay may overheat, risking a stall.",
            componentAffected = "FUEL SYSTEM", dateAnnounced = daysAgo(900), status = RecallStatus.OUTSTANDING,
            recallSource = RecallSource.NHTSA_API),
    )

    private fun entry(
        id: String, vehicleId: String, type: EntryType, days: Long, odo: Int, cost: Double?,
        shop: String? = null, diy: Boolean? = null, notes: String? = null, isResolved: Boolean? = null,
        details: Map<String, Any?> = emptyMap(),
    ): Entry {
        val at = daysAgo(days)
        return Entry(
            id = id, vehicleId = vehicleId, userId = userId, entryType = type, entryDate = at,
            odometerReading = odo, cost = cost, isDiy = diy, shopName = shop, notes = notes,
            isResolved = isResolved, details = details, createdAt = at, updatedAt = at,
        )
    }

    private fun daysAgo(days: Long): Instant = now.minus(Duration.ofDays(days))

    private fun daysFromNow(days: Long): Instant = now.plus(Duration.ofDays(days))

    companion object {
        const val VIPER_ID = "seed-viper"
        const val SQ5_ID = "seed-sq5"
    }
}
