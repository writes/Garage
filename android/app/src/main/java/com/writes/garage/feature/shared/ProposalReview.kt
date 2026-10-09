package com.writes.garage.feature.shared

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Validators
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.ReceiptProposal
import com.writes.garage.core.model.VoiceProposal
import com.writes.garage.feature.entry.EntryDetailsMapper
import com.writes.garage.feature.entry.EntryFieldSpecs
import com.writes.garage.feature.entry.EntryFormState
import com.writes.garage.feature.entry.EntryFormValidator
import com.writes.garage.feature.entry.FieldDef
import com.writes.garage.feature.entry.FieldKind
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId

/**
 * Editable copy of an AI proposal (receipt or voice). The user reviews / corrects these fields; nothing is
 * persisted until they confirm, at which point [ProposalForm.toEntry] builds the entry.
 */
data class ProposalFormState(
    val type: EntryType,
    val date: LocalDate,
    val odometer: String,
    val cost: String,
    val shop: String,
    val notes: String,
    val isDiy: Boolean,
    /** Type-specific fields keyed by [EntryFieldSpecs] keys (raw strings), seeded from the server's typed fields. */
    val details: Map<String, String> = emptyMap(),
    /** The server's raw typed fields; re-seeded when the user switches type. */
    val serverDetails: Map<String, Any?> = emptyMap(),
    val errors: Map<String, String> = emptyMap(),
)

object ProposalForm {
    const val ODOMETER = "odometer"
    const val COST = "cost"

    private fun money(d: Double?): String =
        d?.let { BigDecimal.valueOf(it).setScale(2, java.math.RoundingMode.HALF_UP).toPlainString() }.orEmpty()

    fun fromReceipt(p: ReceiptProposal, fallbackOdometer: Int, zone: ZoneId = ZoneId.systemDefault()) = ProposalFormState(
        type = p.entryType,
        date = p.entryDate.atZone(zone).toLocalDate(),
        odometer = (p.odometerReading ?: fallbackOdometer).toString(),
        cost = money(p.cost),
        shop = p.shopName.orEmpty(),
        notes = p.notes.orEmpty(),
        isDiy = p.isDiy == true,
        details = seedDetails(p.entryType, p.details, p.shopName, p.cost),
        serverDetails = p.details,
    )

    fun fromVoice(p: VoiceProposal, fallbackOdometer: Int, zone: ZoneId = ZoneId.systemDefault()) = ProposalFormState(
        type = p.entryType,
        date = p.entryDate.atZone(zone).toLocalDate(),
        odometer = (p.odometerReading ?: fallbackOdometer).toString(),
        cost = money(p.cost),
        shop = p.shopName.orEmpty(),
        notes = p.notes.orEmpty(),
        isDiy = p.isDiy == true,
        details = seedDetails(p.entryType, p.details, p.shopName, p.cost),
        serverDetails = p.details,
    )

    /** Re-types the form: the type-specific fields are re-seeded from the server's proposal for [type]. */
    fun withType(s: ProposalFormState, type: EntryType): ProposalFormState =
        s.copy(
            type = type,
            details = seedDetails(type, s.serverDetails, s.shop.ifBlank { null }, parseCost(s.cost)),
            errors = s.errors.filterKeys { !it.startsWith("detail:") },
        )

    private val maintenanceKeywords: List<Pair<List<String>, String>> = listOf(
        listOf("cabin air filter", "cabin filter", "pollen filter") to "cabin_air_filter",
        listOf("brake fluid") to "brake_fluid_flush",
        listOf("air filter", "engine filter") to "air_filter",
        listOf("spark plug") to "spark_plugs",
        listOf("wiper") to "wiper_blades",
        listOf("battery") to "battery_replaced",
        listOf("coolant flush", "coolant") to "coolant_flush",
        listOf("radiator", "cooling system") to "radiator_cooling_system",
        listOf("transmission") to "transmission_service",
        listOf("differential", "diff service", "diff fluid") to "differential_service",
        listOf("belt", "hose") to "belts_and_hoses",
        listOf("fuel system", "fuel injector", "injector clean") to "fuel_system_service",
        listOf("rotate", "rotation", "balance") to "rotate_balance_tires",
    )

    /** Port of iOS `MaintenanceItemMatcher`: conservative keyword match, null on a miss. */
    fun matchMaintenanceItem(workItem: String): String? {
        val lowered = workItem.lowercase()
        return maintenanceKeywords.firstOrNull { (kws, _) -> kws.any { lowered.contains(it) } }?.second
    }

    private fun str(v: Any?): String? = (v as? String)?.trim()?.takeIf { it.isNotEmpty() }

    private fun num(v: Any?): String? = (v as? Number)?.toDouble()?.takeIf { it > 0 && it.isFinite() }?.let {
        BigDecimal.valueOf(it).stripTrailingZeros().toPlainString()
    }

    private fun choiceOrNull(type: EntryType, key: String, value: String?): String? =
        value?.takeIf { v -> EntryFieldSpecs.forType(type).fields.firstOrNull { it.key == key }?.choices?.any { it.value == v } == true }

    /**
     * Maps the server's typed fields (`workItem`, `brand`, `serviceAction`, ...) onto the entry-form keys iOS
     * decodes (port of the iOS `seedProposal` methods), on top of the type's field defaults.
     */
    fun seedDetails(type: EntryType, server: Map<String, Any?>, shop: String?, cost: Double?): Map<String, String> {
        val out = LinkedHashMap(EntryDetailsMapper.defaults(type))
        fun put(key: String, v: String?) { if (v != null) out[key] = v }
        val workItem = str(server["workItem"])
        val brand = str(server["brand"])
        val model = str(server["productModel"])
        val grade = str(server["oilGrade"])
        val quarts = num(server["quantityQuarts"])
        val action = str(server["serviceAction"])
        val nextDue = (server["nextDueOdometer"] as? Number)?.toInt()?.takeIf { it > 0 }
        when (type) {
            EntryType.OIL_CHANGE -> {
                put("oilBrand", brand); put("oilGrade", grade); put("quantityQuarts", quarts)
            }
            EntryType.OIL_CONSUMPTION -> {
                put("amountAddedQuarts", quarts); put("oilBrand", brand); put("oilGrade", grade)
            }
            EntryType.FUEL -> put("stationName", shop)
            EntryType.TIRE -> {
                put("actionType", choiceOrNull(type, "actionType", action))
                put("tireBrand", brand); put("tireModel", model)
                put("tireSizeFront", str(server["tireSizeFront"])); put("tireSizeRear", str(server["tireSizeRear"]))
            }
            EntryType.BRAKE -> {
                put("action", choiceOrNull(type, "action", action)); put("padBrand", brand)
            }
            EntryType.MAINTENANCE -> {
                workItem?.let { matchMaintenanceItem(it) }?.let { put("item", it) }
                nextDue?.let { put("nextDueMileage", it.toString()) }
            }
            EntryType.REPAIR -> put("title", workItem)
            EntryType.UPGRADE -> {
                put("title", workItem); put("brand", brand)
                put("category", choiceOrNull(type, "category", str(server["upgradeCategory"])))
            }
            else -> Unit
        }
        return out
    }

    /** The type-specific fields shown in the review: required ones, pickers, and anything the AI filled in. */
    fun reviewFields(s: ProposalFormState): List<FieldDef> =
        EntryFieldSpecs.forType(s.type).fields.filter { f ->
            f.isVisible(s.details) &&
                (f.isRequired(s.details) || f.kind == FieldKind.CHOICE || s.details[f.key].orEmpty().isNotBlank())
        }

    fun parseCost(text: String): Double? =
        text.filterNot { it == '$' || it == ',' || it.isWhitespace() }.toDoubleOrNull()?.takeIf { it.isFinite() }

    /** Empty map = valid. */
    fun validate(s: ProposalFormState): Map<String, String> {
        val errors = LinkedHashMap<String, String>()
        if (Validators.parseOdometer(s.odometer) == null) errors[ODOMETER] = "Enter 0 to 2,000,000"
        if (s.cost.isNotBlank()) {
            val c = parseCost(s.cost)
            if (c == null || c < 0) errors[COST] = "Enter a non-negative amount"
        }
        val detailState = EntryFormState(type = s.type, odometer = s.odometer, cost = s.cost, details = s.details, loading = false)
        EntryFormValidator.validate(detailState).forEach { (k, v) -> if (k.startsWith("detail:")) errors[k] = v }
        return errors
    }

    /**
     * Builds the entry the user approved. Type-specific [ProposalFormState.details] go through
     * [EntryDetailsMapper.toDetails] so the saved map has exactly the keys (and always-written empties) iOS decodes.
     */
    fun toEntry(
        s: ProposalFormState,
        vehicleId: String,
        attachmentPaths: List<String> = emptyList(),
        zone: ZoneId = ZoneId.systemDefault(),
        /** Pre-generated id so uploaded attachments live under the saved entry's own Storage folder. */
        entryId: String = "",
    ): Entry {
        val details = EntryDetailsMapper.toDetails(s.type, s.details, emptyMap(), zone).toMutableMap()
        val cost = parseCost(s.cost)
        if (s.type == EntryType.FUEL) {
            val gallons = (details["gallons"] as? Number)?.toDouble()
            val price = (details["pricePerGallon"] as? Number)?.toDouble()
            val total = cost ?: if (gallons != null && price != null) Math.round(gallons * price * 100) / 100.0 else 0.0
            details["totalCost"] = total
        }
        val resolved = when (s.type) {
            EntryType.REPAIR, EntryType.MAINTENANCE -> details["status"] == "resolved"
            else -> null
        }
        return Entry(
            id = entryId, vehicleId = vehicleId, userId = "",
            entryType = s.type,
            entryDate = s.date.atTime(12, 0).atZone(zone).toInstant(),
            odometerReading = Validators.parseOdometer(s.odometer) ?: 0,
            cost = cost,
            isDiy = if (s.isDiy) true else null,
            shopName = s.shop.trim().ifBlank { null },
            notes = s.notes.trim().ifBlank { null },
            isResolved = resolved,
            attachmentPaths = attachmentPaths,
            details = details,
        )
    }
}

/** Editable fields of a proposal. Stateless: the host ViewModel owns [state]. */
@Composable
fun ProposalEditor(
    state: ProposalFormState,
    onChange: (ProposalFormState) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ChoiceField(
            label = "Type",
            options = EntryType.entries.map { ChoiceOption(it.wire, it.displayName) },
            selected = state.type.wire,
            onSelect = { w -> EntryType.fromWire(w)?.let { onChange(ProposalForm.withType(state, it)) } },
            required = true,
        )
        DateField(
            label = "Date", date = state.date, required = true,
            onPick = { d -> if (d != null) onChange(state.copy(date = d)) },
        )
        FormTextField(
            "Odometer (mi)", state.odometer, { onChange(state.copy(odometer = it, errors = state.errors - ProposalForm.ODOMETER)) },
            error = state.errors[ProposalForm.ODOMETER], keyboardType = KeyboardType.Number, required = true,
        )
        FormTextField(
            "Cost", state.cost, { onChange(state.copy(cost = it, errors = state.errors - ProposalForm.COST)) },
            error = state.errors[ProposalForm.COST], keyboardType = KeyboardType.Decimal,
        )
        ProposalForm.reviewFields(state).forEach { f ->
            ProposalDetailField(
                f, state.details[f.key].orEmpty(), state.errors[EntryFormValidator.detailKey(f.key)], f.isRequired(state.details),
            ) { v ->
                onChange(state.copy(details = state.details + (f.key to v), errors = state.errors - EntryFormValidator.detailKey(f.key)))
            }
        }
        FormTextField("Shop", state.shop, { onChange(state.copy(shop = it)) })
        FormTextField("Notes", state.notes, { onChange(state.copy(notes = it)) }, singleLine = false)
        SwitchRow("Did it myself", state.isDiy, { onChange(state.copy(isDiy = it)) })
    }
}

@Composable
private fun ProposalDetailField(f: FieldDef, value: String, error: String?, required: Boolean, onChange: (String) -> Unit) {
    when (f.kind) {
        FieldKind.TEXT, FieldKind.DATE -> FormTextField(f.label, value, onChange, error = error, required = required)
        FieldKind.MULTILINE, FieldKind.LIST ->
            FormTextField(f.label, value, onChange, error = error, singleLine = false, required = required)
        FieldKind.INTEGER -> FormTextField(
            f.label, value, { v -> onChange(v.filter(Char::isDigit)) },
            error = error, keyboardType = KeyboardType.Number, required = required,
        )
        FieldKind.DECIMAL -> FormTextField(
            f.label, value, { v -> onChange(v.filter { c -> c.isDigit() || c == '.' }) },
            error = error, keyboardType = KeyboardType.Decimal, required = required,
        )
        FieldKind.BOOLEAN -> SwitchRow(f.label, value == "true", { onChange(it.toString()) })
        FieldKind.CHOICE -> ChoiceField(
            f.label, f.choices.map { ChoiceOption(it.value, it.label) }, value, onChange, error = error, required = required,
        )
    }
}
