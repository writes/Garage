package com.writes.garage.feature.entry

import com.writes.garage.core.domain.Validators
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Vehicle
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** UI state of the add/edit entry form. All inputs are raw strings; [EntryFormValidator] decides validity. */
data class EntryFormState(
    val vehicleId: String? = null,
    val vehicles: List<Vehicle> = emptyList(),
    val type: EntryType = EntryType.MAINTENANCE,
    val date: LocalDate = LocalDate.now(),
    val odometer: String = "",
    val cost: String = "",
    val shop: String = "",
    val notes: String = "",
    val isDiy: Boolean = false,
    /** Type-specific fields keyed by [FieldDef.key]; booleans as "true"/"false", lists comma separated, dates ISO. */
    val details: Map<String, String> = emptyMap(),
    /** Field errors: [EntryFormValidator.ODOMETER], [EntryFormValidator.COST], or `detail:<key>`. */
    val errors: Map<String, String> = emptyMap(),
    val warnings: List<String> = emptyList(),
    val loading: Boolean = true,
    val saving: Boolean = false,
    val formError: String? = null,
    val notFound: Boolean = false,
    /** Already-uploaded attachment paths of the entry being edited (minus those queued for removal). */
    val attachmentPaths: List<String> = emptyList(),
    /** Picked but not yet uploaded; uploaded at save time under the entry's own folder. */
    val pendingAttachments: List<PendingAttachment> = emptyList(),
    /** Oil-analysis PDF import in flight / outcome. */
    val importing: Boolean = false,
    val importNotice: String? = null,
    /** An import was attempted without AI consent: show the consent dialog. */
    val needsAiConsent: Boolean = false,
    /** The free allowance for imports is used up (or the server said Pro is required): route to the paywall. */
    val needsUpgrade: Boolean = false,
)

/** A picked photo/PDF (content or FileProvider uri) waiting for save. */
data class PendingAttachment(val uri: String, val mimeType: String, val displayName: String)

object EntryFormValidator {
    const val ODOMETER = "odometer"
    const val COST = "cost"

    fun detailKey(fieldKey: String) = "detail:$fieldKey"

    /** Lenient money/number parser: tolerates `$`, thousands separators and spaces. */
    fun parseDecimal(text: String): Double? =
        text.filterNot { it == '$' || it == ',' || it.isWhitespace() }
            .toDoubleOrNull()?.takeIf { it.isFinite() }

    /**
     * Empty map = valid. [unchangedLegacy] holds the raw detail values the entry was loaded with: a choice value outside
     * today's vocabulary is tolerated only while it is untouched (so older clients' entries stay editable), never newly typed.
     */
    fun validate(s: EntryFormState, unchangedLegacy: Map<String, String> = emptyMap()): Map<String, String> {
        val errors = LinkedHashMap<String, String>()

        if (s.odometer.isBlank()) errors[ODOMETER] = "Required"
        else if (Validators.parseOdometer(s.odometer) == null) errors[ODOMETER] = "Enter 0 to 2,000,000"

        if (s.cost.isNotBlank()) {
            val c = parseDecimal(s.cost)
            if (c == null || c < 0) errors[COST] = "Enter a non-negative amount"
        }

        for (f in EntryFieldSpecs.forType(s.type).fields) {
            if (!f.isVisible(s.details)) continue
            val v = s.details[f.key].orEmpty().trim()
            val key = detailKey(f.key)
            if (v.isEmpty()) {
                if (f.isRequired(s.details)) errors[key] = "Required"
                continue
            }
            val err = when (f.kind) {
                FieldKind.INTEGER -> if (v.toLongOrNull()?.let { it in 0..Int.MAX_VALUE } == true) null else "Whole number, 0 or more"
                FieldKind.DECIMAL -> {
                    val d = parseDecimal(v)
                    when {
                        d == null || d < 0 -> "Number, 0 or more"
                        f.max != null && d > f.max -> "At most ${f.max.toInt()}"
                        else -> null
                    }
                }
                FieldKind.DATE -> if (runCatching { LocalDate.parse(v) }.isSuccess) null else "Invalid date"
                // A stored value outside the vocabulary (e.g. a seed typo) would silently change meaning on edit.
                FieldKind.CHOICE ->
                    if (f.choices.any { it.value == v } || unchangedLegacy[f.key] == v) null else "Choose one of the options"
                else -> null
            } ?: f.validate?.invoke(v)
            if (err != null) errors[key] = err
        }
        return errors
    }
}

/** Converts between an entry's typed `details` map and the form's raw strings. */
object EntryDetailsMapper {
    /** Fresh-form values: field defaults (and a fuel grade seed). */
    fun defaults(type: EntryType, fuelGrade: String? = null): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for (f in EntryFieldSpecs.forType(type).fields) {
            val d = f.default ?: continue
            out[f.key] = d
        }
        if (type == EntryType.FUEL && fuelGrade != null) out["fuelGrade"] = fuelGrade
        return out
    }

    fun toRaw(type: EntryType, details: Map<String, Any?>, zone: ZoneId): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for (f in EntryFieldSpecs.forType(type).fields) {
            val s = display(getPath(details, f.key), zone) ?: continue
            if (s.isNotEmpty()) out[f.key] = s
        }
        return out
    }

    /**
     * Typed `details` for [raw]. [base] (the entry's previous details, empty when the type changed) is carried
     * over so keys this form does not know about (older clients, AI proposals) survive an edit.
     */
    fun toDetails(type: EntryType, raw: Map<String, String>, base: Map<String, Any?>, zone: ZoneId): Map<String, Any?> {
        val spec = EntryFieldSpecs.forType(type)
        val out = deepMutable(base)
        for (f in spec.fields) {
            if (!f.isVisible(raw)) {
                removePath(out, f.key)
                continue
            }
            val v = raw[f.key].orEmpty().trim()
            if (v.isEmpty()) {
                if (f.alwaysWrite) setPath(out, f.key, emptyValue(f)) else removePath(out, f.key)
                continue
            }
            setPath(out, f.key, parse(f, v, zone))
        }
        for (obj in spec.ensureObjects) if (out[obj] !is Map<*, *>) out[obj] = LinkedHashMap<String, Any?>()
        return out
    }

    private fun emptyValue(f: FieldDef): Any? = when (f.kind) {
        FieldKind.BOOLEAN -> false
        FieldKind.LIST -> emptyList<String>()
        FieldKind.INTEGER -> 0
        FieldKind.DECIMAL -> 0.0
        FieldKind.DATE -> null
        else -> ""
    }

    private fun parse(f: FieldDef, v: String, zone: ZoneId): Any? = when (f.kind) {
        FieldKind.INTEGER -> v.toLong().toInt()
        FieldKind.DECIMAL -> EntryFormValidator.parseDecimal(v)
        FieldKind.BOOLEAN -> v == "true"
        FieldKind.LIST -> v.split(',', '\n').map { it.trim() }.filter { it.isNotEmpty() }
        FieldKind.DATE -> LocalDate.parse(v).atStartOfDay(zone).toInstant()
        else -> v
    }

    private fun display(v: Any?, zone: ZoneId): String? = when (v) {
        null -> null
        is Boolean -> v.toString()
        is Int, is Long -> v.toString()
        is Number -> v.toDouble().let { d ->
            if (d == Math.floor(d) && Math.abs(d) < 1e15) d.toLong().toString()
            else BigDecimal.valueOf(d).stripTrailingZeros().toPlainString()
        }
        is Instant -> v.atZone(zone).toLocalDate().toString()
        is List<*> -> v.joinToString(", ") { it.toString() }
        else -> v.toString()
    }

    @Suppress("UNCHECKED_CAST")
    internal fun getPath(map: Map<String, Any?>, path: String): Any? {
        var cur: Any? = map
        for (part in path.split('.')) cur = (cur as? Map<String, Any?>)?.get(part) ?: return null
        return cur
    }

    @Suppress("UNCHECKED_CAST")
    private fun setPath(map: MutableMap<String, Any?>, path: String, value: Any?) {
        if (value == null) return removePath(map, path)
        val parts = path.split('.')
        var cur = map
        for (p in parts.dropLast(1)) {
            val next = cur[p]
            cur = if (next is MutableMap<*, *>) next as MutableMap<String, Any?> else LinkedHashMap<String, Any?>().also { cur[p] = it }
        }
        cur[parts.last()] = value
    }

    @Suppress("UNCHECKED_CAST")
    private fun removePath(map: MutableMap<String, Any?>, path: String) {
        val parts = path.split('.')
        var cur = map
        for (p in parts.dropLast(1)) cur = (cur[p] as? MutableMap<String, Any?>) ?: return
        cur.remove(parts.last())
    }

    private fun deepMutable(m: Map<String, Any?>): MutableMap<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        for ((k, v) in m) out[k] = if (v is Map<*, *>) deepMutable(v.entries.associate { it.key.toString() to it.value }) else v
        return out
    }
}

/** Read-only presentation of an entry's details (labels from the field spec, legacy keys shown verbatim). */
object EntryDetailsPresenter {
    fun rows(entry: Entry, zone: ZoneId = ZoneId.systemDefault()): List<Pair<String, String>> {
        val spec = EntryFieldSpecs.forType(entry.entryType)
        val flat = LinkedHashMap<String, Any?>()
        flatten("", entry.details, flat)
        val known = spec.fields.map { it.key }
        val ordered = known.filter { flat.containsKey(it) } + flat.keys.filterNot { it in known }.sorted()
        return ordered.mapNotNull { key ->
            val field = spec.fields.firstOrNull { it.key == key }
            val shown = present(flat[key], field, zone)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val label = field?.let { f -> f.section?.let { "$it: ${f.label}" } ?: f.label } ?: key
            label to shown
        }
    }

    private fun flatten(prefix: String, map: Map<*, *>, out: MutableMap<String, Any?>) {
        for ((k, v) in map) {
            val key = if (prefix.isEmpty()) k.toString() else "$prefix.$k"
            if (v is Map<*, *>) flatten(key, v, out) else out[key] = v
        }
    }

    private fun present(v: Any?, f: FieldDef?, zone: ZoneId): String? {
        val raw = when (v) {
            null -> return null
            is Boolean -> if (v) "Yes" else "No"
            is Instant -> v.atZone(zone).toLocalDate().toString()
            is List<*> -> v.joinToString(", ")
            is Number -> v.toDouble().let { d -> if (d == Math.floor(d) && Math.abs(d) < 1e15) d.toLong().toString() else BigDecimal.valueOf(d).stripTrailingZeros().toPlainString() }
            else -> v.toString()
        }
        return f?.choices?.firstOrNull { it.value == raw }?.label ?: raw
    }
}
