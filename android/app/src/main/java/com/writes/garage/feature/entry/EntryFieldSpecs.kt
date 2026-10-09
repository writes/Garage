package com.writes.garage.feature.entry

import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.FuelType

enum class FieldKind { TEXT, MULTILINE, INTEGER, DECIMAL, BOOLEAN, CHOICE, LIST, DATE }

data class Choice(val value: String, val label: String)

/**
 * One type-specific field of an entry's `details` map (port of the field sets in
 * `Garage/Core/Models/Entries/`, iOS). [key] may be dotted (`beforeSpecs.frontLeftCamber`) for nested maps.
 *
 * [required] is the UI/validation rule; [alwaysWrite] marks fields that are non-optional in the iOS Codable
 * model, so a blank value is still written (`""`, `false`, `[]`) - otherwise iOS would fail to decode the entry.
 */
data class FieldDef(
    val key: String,
    val label: String,
    val kind: FieldKind,
    val required: Boolean = false,
    val choices: List<Choice> = emptyList(),
    val default: String? = null,
    val section: String? = null,
    val max: Double? = null,
    val alwaysWrite: Boolean = false,
    val visibleWhen: ((Map<String, String>) -> Boolean)? = null,
    val requiredWhen: ((Map<String, String>) -> Boolean)? = null,
    val validate: ((String) -> String?)? = null,
) {
    fun isVisible(raw: Map<String, String>): Boolean = visibleWhen?.invoke(raw) ?: true

    fun isRequired(raw: Map<String, String>): Boolean = required || requiredWhen?.invoke(raw) == true
}

data class EntryTypeSpec(
    val fields: List<FieldDef>,
    /** Nested objects that iOS decodes as non-optional and which must therefore exist even when empty. */
    val ensureObjects: List<String> = emptyList(),
)

object EntryFieldSpecs {
    private val lapTimeRegex = Regex("""^(\d{1,2}:\d{2}(\.\d{1,3})?|\d{1,3}(\.\d{1,3})?)$""")

    val serviceStatus = listOf(
        Choice("unresolved", "Unresolved"),
        Choice("in_progress", "In progress"),
        Choice("resolved", "Resolved"),
    )

    val fuelGrades: List<Choice> = FuelType.entries.map { Choice(it.wire, it.displayName) }

    private val tireActions = listOf(
        Choice("new_install", "New install"),
        Choice("rotation", "Rotation"),
        Choice("tread_depth_reading", "Tread depth reading"),
        Choice("removed", "Removed"),
    )

    private val tirePositions = listOf(
        Choice("fl", "Front left"), Choice("fr", "Front right"),
        Choice("rl", "Rear left"), Choice("rr", "Rear right"),
        Choice("front", "Front axle"), Choice("rear", "Rear axle"), Choice("all_four", "All four"),
    )

    private val brakeActions = listOf(
        Choice("pads_replaced", "Pads replaced"),
        Choice("rotors_replaced", "Rotors replaced"),
        Choice("fluid_flush", "Fluid flush"),
        Choice("inspection", "Inspection"),
    )

    private val brakePositions = listOf(Choice("front", "Front"), Choice("rear", "Rear"), Choice("all", "All"))

    private val maintenanceItems = listOf(
        Choice("air_filter", "Air filter"),
        Choice("cabin_air_filter", "Cabin air filter"),
        Choice("fuel_system_service", "Fuel system service"),
        Choice("rotate_balance_tires", "Rotate & balance tires"),
        Choice("spark_plugs", "Spark plugs"),
        Choice("transmission_service", "Transmission service"),
        Choice("differential_service", "Differential service"),
        Choice("wiper_blades", "Wiper blades"),
        Choice("battery_replaced", "Battery replaced"),
        Choice("radiator_cooling_system", "Radiator / cooling system"),
        Choice("belts_and_hoses", "Belts & hoses"),
        Choice("brake_fluid_flush", "Brake fluid flush"),
        Choice("coolant_flush", "Coolant flush"),
        Choice("other", "Other"),
    )

    private val trackEvents = listOf(
        Choice("hpde", "HPDE"), Choice("timeTrial", "Time trial"), Choice("lapping", "Lapping"), Choice("race", "Race"),
    )

    private val trackConditions = listOf(Choice("dry", "Dry"), Choice("wet", "Wet"), Choice("mixed", "Mixed"))

    private val upgradeCategories = listOf(
        Choice("suspension", "Suspension"), Choice("engine", "Engine"), Choice("aero", "Aero"),
        Choice("interior", "Interior"), Choice("wheels", "Wheels"), Choice("other", "Other"),
    )

    private val dmeReportTypes = listOf(
        Choice("over_revs", "Over-revs"), Choice("fault_codes", "Fault codes"), Choice("other", "Other"),
    )

    private fun text(key: String, label: String, required: Boolean = false, always: Boolean = false, section: String? = null) =
        FieldDef(key, label, FieldKind.TEXT, required = required, alwaysWrite = always, section = section)

    private fun multiline(key: String, label: String) = FieldDef(key, label, FieldKind.MULTILINE)

    private fun int(key: String, label: String, required: Boolean = false, default: String? = null, always: Boolean = false) =
        FieldDef(key, label, FieldKind.INTEGER, required = required, default = default, alwaysWrite = always)

    private fun dec(key: String, label: String, required: Boolean = false, max: Double? = null, section: String? = null) =
        FieldDef(key, label, FieldKind.DECIMAL, required = required, max = max, section = section)

    private fun choice(
        key: String,
        label: String,
        choices: List<Choice>,
        default: String,
        visibleWhen: ((Map<String, String>) -> Boolean)? = null,
    ) = FieldDef(
        key, label, FieldKind.CHOICE, required = true, choices = choices, default = default,
        alwaysWrite = true, visibleWhen = visibleWhen,
    )

    private val alignmentSpecFields = listOf(
        "frontLeftCamber" to "Front left camber", "frontRightCamber" to "Front right camber",
        "rearLeftCamber" to "Rear left camber", "rearRightCamber" to "Rear right camber",
        "frontLeftToe" to "Front left toe", "frontRightToe" to "Front right toe",
        "rearLeftToe" to "Rear left toe", "rearRightToe" to "Rear right toe",
        "frontLeftCaster" to "Front left caster", "frontRightCaster" to "Front right caster",
    )

    private val wearMetals = listOf(
        "aluminum", "chromium", "iron", "copper", "lead", "tin", "molybdenum", "nickel",
        "manganese", "silver", "titanium", "silicon", "sodium", "potassium",
    )

    private val specs: Map<EntryType, EntryTypeSpec> = mapOf(
        EntryType.OIL_CHANGE to EntryTypeSpec(
            listOf(
                text("oilBrand", "Oil brand", required = true, always = true),
                text("oilGrade", "Oil grade (e.g. 5W-30)", required = true, always = true),
                dec("quantityQuarts", "Quantity (quarts)", required = true),
                text("filterBrand", "Filter brand"),
            ),
        ),
        EntryType.OIL_CONSUMPTION to EntryTypeSpec(
            listOf(
                dec("amountAddedQuarts", "Amount added (quarts)", required = true),
                dec("runningTotalSinceLastChange", "Running total since last change (quarts)"),
                text("oilBrand", "Oil brand"),
                text("oilGrade", "Oil grade"),
            ),
        ),
        EntryType.OIL_ANALYSIS to EntryTypeSpec(
            listOf(
                text("labName", "Lab name", required = true, always = true),
                int("milesOnOil", "Miles on oil"),
                text("viscosity", "Viscosity"),
                dec("insolubles", "Insolubles"),
            ) + wearMetals.map { dec(it, it.replaceFirstChar(Char::uppercase), section = "Wear metals (ppm)") } +
                multiline("labRecommendation", "Lab recommendation"),
        ),
        EntryType.FUEL to EntryTypeSpec(
            listOf(
                dec("gallons", "Gallons", required = true),
                dec("pricePerGallon", "Price per gallon", required = true),
                text("stationName", "Station"),
                FieldDef(
                    "fuelGrade", "Fuel grade", FieldKind.CHOICE, required = true, choices = fuelGrades,
                    default = FuelType.PREMIUM_91.wire, alwaysWrite = true,
                ),
            ),
        ),
        EntryType.TIRE to EntryTypeSpec(
            listOf(
                choice("actionType", "Action", tireActions, "new_install"),
                FieldDef(
                    "tireBrand", "Tire brand", FieldKind.TEXT, alwaysWrite = true,
                    requiredWhen = { it["actionType"] == "new_install" },
                ),
                FieldDef(
                    "tireModel", "Tire model", FieldKind.TEXT, alwaysWrite = true,
                    requiredWhen = { it["actionType"] == "new_install" },
                ),
                choice("position", "Position", tirePositions, "all_four"),
                text("tireSetId", "Tire set id"),
                text("tireSizeFront", "Front size"),
                text("tireSizeRear", "Rear size"),
                text("compound", "Compound"),
                text("treadwearRating", "Treadwear rating"),
                int("heatCycles", "Heat cycles"),
                text("treadDepthFL", "Front left", section = "Tread depth (e.g. 6/32)"),
                text("treadDepthFR", "Front right", section = "Tread depth (e.g. 6/32)"),
                text("treadDepthRL", "Rear left", section = "Tread depth (e.g. 6/32)"),
                text("treadDepthRR", "Rear right", section = "Tread depth (e.g. 6/32)"),
            ),
        ),
        EntryType.BRAKE to EntryTypeSpec(
            listOf(
                choice("action", "Action", brakeActions, "pads_replaced"),
                choice("position", "Position", brakePositions, "front"),
                text("padBrand", "Pad brand"),
                text("padCompound", "Pad compound"),
                text("rotorBrand", "Rotor brand"),
                dec("padThicknessAtInstallMM", "Pad thickness at install (mm)"),
                dec("frontPadPct", "Front pad remaining (%)", max = 100.0),
                dec("rearPadPct", "Rear pad remaining (%)", max = 100.0),
                dec("frontRotorPct", "Front rotor remaining (%)", max = 100.0),
                dec("rearRotorPct", "Rear rotor remaining (%)", max = 100.0),
                FieldDef("fluidFlushed", "Brake fluid flushed", FieldKind.BOOLEAN, default = "false", alwaysWrite = true),
            ),
        ),
        EntryType.ALIGNMENT to EntryTypeSpec(
            listOf(
                multiline("shopNotes", "Shop notes"),
                text("frontCaster", "Front caster"),
            ) + listOf("beforeSpecs" to "Before", "afterSpecs" to "After").flatMap { (obj, title) ->
                alignmentSpecFields.map { (k, l) -> text("$obj.$k", l, section = "$title alignment") }
            },
            ensureObjects = listOf("beforeSpecs", "afterSpecs"),
        ),
        EntryType.MAINTENANCE to EntryTypeSpec(
            listOf(
                choice("item", "Item", maintenanceItems, "air_filter"),
                FieldDef(
                    "otherLabel", "Describe the service", FieldKind.TEXT, required = true,
                    visibleWhen = { it["item"] == "other" },
                ),
                int("nextDueMileage", "Next due (miles)"),
                FieldDef("nextDueDate", "Next due date", FieldKind.DATE),
                multiline("symptomDescription", "Symptom"),
                multiline("resolutionDescription", "Resolution"),
                choice("status", "Status", serviceStatus, "resolved"),
            ),
        ),
        EntryType.REPAIR to EntryTypeSpec(
            listOf(
                text("title", "Title", required = true, always = true),
                multiline("symptomDescription", "Symptom"),
                multiline("resolutionDescription", "Resolution"),
                choice("status", "Status", serviceStatus, "resolved"),
                FieldDef("replacedParts", "Replaced parts (comma separated)", FieldKind.LIST, alwaysWrite = true),
            ),
        ),
        EntryType.TRACK_DAY to EntryTypeSpec(
            listOf(
                text("venueName", "Venue", required = true, always = true),
                choice("eventType", "Event type", trackEvents, "hpde"),
                text("runGroup", "Run group"),
                int("numberOfLaps", "Number of laps"),
                FieldDef(
                    "bestLapTime", "Best lap (m:ss.sss)", FieldKind.TEXT,
                    validate = { if (lapTimeRegex.matches(it.trim())) null else "Use m:ss.sss, e.g. 1:34.821" },
                ),
                choice("conditions", "Conditions", trackConditions, "dry"),
                text("tireSetId", "Tire set id"),
                dec("fuelUsedGallons", "Fuel used (gallons)"),
                int("heatCyclesAdded", "Heat cycles added", default = "0", always = true),
                multiline("carObservations", "Car observations"),
                multiline("driverNotes", "Driver notes"),
            ),
        ),
        EntryType.UPGRADE to EntryTypeSpec(
            listOf(
                text("title", "Title", required = true, always = true),
                text("brand", "Brand"),
                text("partNumber", "Part number"),
                choice("category", "Category", upgradeCategories, "other"),
            ),
        ),
        EntryType.DME_REPORT to EntryTypeSpec(
            listOf(
                text("providerName", "Provider", required = true, always = true),
                choice("reportType", "Report type", dmeReportTypes, "fault_codes"),
                multiline("summary", "Summary"),
            ),
        ),
    )

    fun forType(type: EntryType): EntryTypeSpec = specs.getValue(type)

    /** Human label for a stored `details` key (falls back to the raw key). */
    fun labelFor(type: EntryType, key: String): String =
        forType(type).fields.firstOrNull { it.key == key }?.label ?: key
}
