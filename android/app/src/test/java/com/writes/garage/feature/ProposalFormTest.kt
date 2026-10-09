package com.writes.garage.feature

import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.feature.shared.ProposalForm
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class ProposalFormTest {
    private val proposal = ReceiptProposal(
        token = "t", vehicleId = "v1", entryType = EntryType.OIL_CHANGE,
        entryDate = Instant.parse("2026-03-04T08:00:00Z"), odometerReading = null, cost = 12.5,
        details = mapOf("brand" to "X", "oilGrade" to "5W-30", "quantityQuarts" to 5.0),
    )

    @Test
    fun fallsBackToVehicleOdometerAndFormatsMoney() {
        val f = ProposalForm.fromReceipt(proposal, 5000, ZoneOffset.UTC)
        assertEquals("5000", f.odometer)
        assertEquals("12.50", f.cost)
        assertEquals("2026-03-04", f.date.toString())
    }

    @Test
    fun validateAndParseLenientMoney() {
        val f = ProposalForm.fromReceipt(proposal, 5000, ZoneOffset.UTC)
        assertTrue(ProposalForm.validate(f).isEmpty())
        assertEquals(1234.5, ProposalForm.parseCost("\$1,234.50")!!, 0.0)
        assertEquals(setOf("cost"), ProposalForm.validate(f.copy(cost = "-3")).keys)
        assertTrue(ProposalForm.validate(f.copy(cost = "")).isEmpty())
    }

    @Test
    fun toEntryWritesIosDecodableOilDetails() {
        val p = proposal.copy(details = mapOf("brand" to "Mobil 1", "oilGrade" to "5W-30", "quantityQuarts" to 5.0))
        val f = ProposalForm.fromReceipt(p, 5000, ZoneOffset.UTC).copy(shop = "  ", isDiy = false)
        assertEquals("Mobil 1", f.details["oilBrand"])
        val e = ProposalForm.toEntry(f, "v1", listOf("p"), ZoneOffset.UTC)
        assertEquals("Mobil 1", e.details["oilBrand"])
        assertEquals("5W-30", e.details["oilGrade"])
        assertEquals(5.0, (e.details["quantityQuarts"] as Number).toDouble(), 0.0)
        assertTrue("server-only key leaked", "brand" !in e.details)
        assertEquals(listOf("p"), e.attachmentPaths)
        assertNull(e.shopName)
        assertNull(e.isDiy)
        assertEquals(Instant.parse("2026-03-04T12:00:00Z"), e.entryDate)
    }

    @Test
    fun requiredDetailFieldsBlockSave() {
        val f = ProposalForm.fromReceipt(proposal.copy(details = emptyMap()), 5000, ZoneOffset.UTC)
        val errors = ProposalForm.validate(f)
        assertEquals(setOf("detail:oilBrand", "detail:oilGrade", "detail:quantityQuarts"), errors.keys)
    }

    @Test
    fun switchingTypeReseedsFromServerFields() {
        val p = proposal.copy(entryType = EntryType.MAINTENANCE, details = mapOf("workItem" to "Cabin air filter", "nextDueOdometer" to 20000, "brand" to "X"))
        val f = ProposalForm.fromReceipt(p, 5000, ZoneOffset.UTC)
        assertEquals("cabin_air_filter", f.details["item"])
        assertEquals("20000", f.details["nextDueMileage"])
        val repair = ProposalForm.withType(f, EntryType.REPAIR)
        assertEquals("Cabin air filter", repair.details["title"])
        val e = ProposalForm.toEntry(repair, "v1", zone = ZoneOffset.UTC)
        assertEquals("Cabin air filter", e.details["title"])
        assertEquals(true, e.isResolved)
        assertTrue("item" !in e.details)
    }

    @Test
    fun fuelGetsTotalCostAndGrade() {
        val p = proposal.copy(entryType = EntryType.FUEL, details = emptyMap())
        val f = ProposalForm.fromReceipt(p, 5000, ZoneOffset.UTC).copy(details = mapOf("gallons" to "10", "pricePerGallon" to "4", "fuelGrade" to "premium_91"))
        val e = ProposalForm.toEntry(f, "v1", zone = ZoneOffset.UTC)
        assertEquals(12.5, e.details["totalCost"] as Double, 0.0)
        assertEquals("premium_91", e.details["fuelGrade"])
    }

    // ---- T20

    @Test
    fun maintenanceKeywordsMapToTheirItems() {
        val table = mapOf(
            "Cabin air filter replaced" to "cabin_air_filter",
            "pollen filter" to "cabin_air_filter",
            "Cabin Filter" to "cabin_air_filter",
            "Engine air filter" to "air_filter",
            "air filter" to "air_filter",
            "Brake fluid flush" to "brake_fluid_flush",
            "Spark plugs x6" to "spark_plugs",
            "Front wiper blades" to "wiper_blades",
            "New battery" to "battery_replaced",
            "Coolant flush" to "coolant_flush",
            "coolant top-off" to "coolant_flush",
            "Radiator replacement" to "radiator_cooling_system",
            "cooling system service" to "radiator_cooling_system",
            "Transmission fluid" to "transmission_service",
            "Differential fluid" to "differential_service",
            "diff service" to "differential_service",
            "Serpentine belt" to "belts_and_hoses",
            "Radiator hose" to "radiator_cooling_system", // radiator outranks hose
            "Fuel system cleaning" to "fuel_system_service",
            "fuel injector clean" to "fuel_system_service",
            "Tire rotation" to "rotate_balance_tires",
            "Wheel balance" to "rotate_balance_tires",
        )
        for ((work, expected) in table) assertEquals(work, expected, ProposalForm.matchMaintenanceItem(work))
    }

    @Test
    fun overlappingKeywordsResolveByTheirOrderAndMissesAreNull() {
        // "brake fluid" must not fall through to anything that would match a bare "fluid".
        assertEquals("brake_fluid_flush", ProposalForm.matchMaintenanceItem("brake fluid"))
        assertTrue(ProposalForm.matchMaintenanceItem("brake fluid") != "air_filter")
        // The cabin variant outranks the generic air filter when both phrases are present.
        assertEquals("cabin_air_filter", ProposalForm.matchMaintenanceItem("engine air filter and cabin air filter"))
        assertNull(ProposalForm.matchMaintenanceItem("detail the interior"))
        assertNull(ProposalForm.matchMaintenanceItem(""))
    }

    private fun seed(type: EntryType, server: Map<String, Any?>, shop: String? = null, cost: Double? = null) =
        ProposalForm.seedDetails(type, server, shop, cost)

    @Test
    fun tireSeedingAcceptsOnlyKnownActions() {
        val ok = seed(EntryType.TIRE, mapOf("serviceAction" to "new_install", "brand" to "Michelin", "productModel" to "PS4", "tireSizeFront" to "255/40R19"))
        assertEquals("new_install", ok["actionType"])
        assertEquals("Michelin", ok["tireBrand"])
        assertEquals("PS4", ok["tireModel"])
        assertEquals("255/40R19", ok["tireSizeFront"])
        val bogus = seed(EntryType.TIRE, mapOf("serviceAction" to "bogus"))
        assertEquals("an out-of-vocabulary action leaves the type's default", com.writes.garage.feature.entry.EntryDetailsMapper.defaults(EntryType.TIRE)["actionType"], bogus["actionType"])
        assertTrue(bogus["actionType"] != "bogus")
    }

    @Test
    fun brakeUpgradeAndOilConsumptionSeeding() {
        val brake = seed(EntryType.BRAKE, mapOf("serviceAction" to "pads_replaced", "brand" to "OEM"))
        assertEquals("pads_replaced", brake["action"])
        assertEquals("OEM", brake["padBrand"])
        assertTrue(seed(EntryType.BRAKE, mapOf("serviceAction" to "caliper_swap"))["action"] != "caliper_swap")

        val up = seed(EntryType.UPGRADE, mapOf("workItem" to "Coilovers", "brand" to "Ohlins", "upgradeCategory" to "suspension"))
        assertEquals("Coilovers", up["title"])
        assertEquals("Ohlins", up["brand"])
        assertEquals("suspension", up["category"])
        assertEquals("other", seed(EntryType.UPGRADE, mapOf("upgradeCategory" to "warp-drive"))["category"])

        val oc = seed(EntryType.OIL_CONSUMPTION, mapOf("quantityQuarts" to 0.5, "brand" to "Mobil 1", "oilGrade" to "0W-40"))
        assertEquals("0.5", oc["amountAddedQuarts"])
        assertEquals("Mobil 1", oc["oilBrand"])
        assertEquals("0W-40", oc["oilGrade"])
    }

    @Test
    fun fuelSeedingUsesTheShopAsTheStation() {
        assertEquals("Shell", seed(EntryType.FUEL, emptyMap(), shop = "Shell")["stationName"])
        assertTrue("stationName" !in seed(EntryType.FUEL, emptyMap(), shop = null))
    }

    @Test
    fun nonPositiveNextDueOdometerAndQuantitiesAreIgnored() {
        val m = seed(EntryType.MAINTENANCE, mapOf("workItem" to "Cabin filter", "nextDueOdometer" to 0))
        assertEquals("cabin_air_filter", m["item"])
        assertTrue("nextDueMileage" !in m)
        assertTrue("nextDueMileage" !in seed(EntryType.MAINTENANCE, mapOf("workItem" to "Cabin filter", "nextDueOdometer" to -5)))
        assertEquals("20000", seed(EntryType.MAINTENANCE, mapOf("nextDueOdometer" to 20_000))["nextDueMileage"])
        assertTrue("quantityQuarts" !in seed(EntryType.OIL_CHANGE, mapOf("quantityQuarts" to 0.0)))
        assertTrue("quantityQuarts" !in seed(EntryType.OIL_CHANGE, mapOf("quantityQuarts" to Double.NaN)))
        assertTrue("oilBrand" !in seed(EntryType.OIL_CHANGE, mapOf("brand" to "   ")))
    }

    @Test
    fun moneyRoundsHalfUpToCents() {
        fun cost(d: Double?) = ProposalForm.fromReceipt(proposal.copy(cost = d), 1, ZoneOffset.UTC).cost
        assertEquals("12.35", cost(12.345))
        assertEquals("12.34", cost(12.344))
        assertEquals("0.01", cost(0.005))
        assertEquals("7.00", cost(7.0))
        assertEquals("", cost(null))
    }

    @Test
    fun fuelWithNeitherCostNorPriceWritesAZeroTotalExplicitly() {
        val p = proposal.copy(entryType = EntryType.FUEL, cost = null, details = emptyMap())
        val f = ProposalForm.fromReceipt(p, 5000, ZoneOffset.UTC).copy(details = mapOf("gallons" to "10", "fuelGrade" to "premium_91"))
        val e = ProposalForm.toEntry(f, "v1", zone = ZoneOffset.UTC)
        assertNull(e.cost)
        // Pinned: iOS's FuelEntry.totalCost is non-optional, so the key is written as 0.0 rather than omitted.
        assertEquals(0.0, e.details["totalCost"] as Double, 0.0)
    }

    @Test
    fun fuelTotalPrefersTheEnteredCostOverGallonsTimesPrice() {
        val p = proposal.copy(entryType = EntryType.FUEL, cost = 50.0, details = emptyMap())
        val f = ProposalForm.fromReceipt(p, 1, ZoneOffset.UTC).copy(details = mapOf("gallons" to "10", "pricePerGallon" to "4", "fuelGrade" to "premium_91"))
        assertEquals(50.0, ProposalForm.toEntry(f, "v1", zone = ZoneOffset.UTC).details["totalCost"] as Double, 0.0)
    }

    @Test
    fun reviewFieldsShowRequiredPickersAndAiFilledValuesOnly() {
        val f = ProposalForm.fromReceipt(proposal.copy(entryType = EntryType.TIRE, details = mapOf("brand" to "Michelin")), 1, ZoneOffset.UTC)
        val keys = ProposalForm.reviewFields(f).map { it.key }
        assertTrue("tireBrand" in keys && "actionType" in keys && "position" in keys)
        assertTrue("treadDepthFL" !in keys)
    }

    @Test
    fun speechErrorsHaveHumanMessages() {
        val s = android.speech.SpeechRecognizer::class.java
        fun d(code: Int) = com.writes.garage.feature.voice.SpeechController.describe(code)
        assertEquals("Didn't catch that. Try again.", d(android.speech.SpeechRecognizer.ERROR_NO_MATCH))
        assertEquals("Didn't catch that. Try again.", d(android.speech.SpeechRecognizer.ERROR_SPEECH_TIMEOUT))
        assertEquals("Microphone permission is required.", d(android.speech.SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS))
        assertEquals("Speech recognition needs a network connection.", d(android.speech.SpeechRecognizer.ERROR_NETWORK))
        assertEquals("Speech recognition needs a network connection.", d(android.speech.SpeechRecognizer.ERROR_NETWORK_TIMEOUT))
        assertEquals("Audio recording error.", d(android.speech.SpeechRecognizer.ERROR_AUDIO))
        assertEquals("Speech recognizer is busy. Try again.", d(android.speech.SpeechRecognizer.ERROR_RECOGNIZER_BUSY))
        assertEquals("Speech recognition failed (code 5).", d(android.speech.SpeechRecognizer.ERROR_CLIENT))
        assertEquals("Speech recognition failed (code 99).", d(99))
        assertTrue(s.simpleName.isNotEmpty())
    }
}
