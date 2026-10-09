package com.writes.garage.core.export

import com.writes.garage.core.model.Entry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral
import java.math.BigDecimal
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Raw entry export, schema-compatible with iOS `CSVExportService` (schema_version 2): RFC 4180 quoting,
 * CRLF line endings, and a spreadsheet-formula guard on free text (a leading `= + - @` or control
 * whitespace gets a `'` prefix so Excel/Sheets never evaluate user text).
 */
@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
object CsvExporter {
    const val SCHEMA_VERSION = "2"
    private const val CRLF = "\r\n"

    val HEADER: List<String> = listOf(
        "schema_version", "id", "vehicleId", "userId", "entryType", "entryDate", "odometerReading", "cost",
        "isDiy", "shopName", "notes", "attachmentPaths", "isResolved", "details", "createdAt", "updatedAt",
    )

    fun export(entries: List<Entry>): String = buildString {
        append(HEADER.joinToString(",")).append(CRLF)
        for (entry in entries) append(row(entry)).append(CRLF)
    }

    fun row(entry: Entry): String = listOf(
        SCHEMA_VERSION,
        entry.id,
        entry.vehicleId,
        entry.userId,
        entry.entryType.wire,
        iso(entry.entryDate),
        entry.odometerReading.toString(),
        entry.cost?.let(::plainNumber).orEmpty(),
        entry.isDiy?.toString().orEmpty(),
        safeFreeText(entry.shopName.orEmpty()),
        safeFreeText(entry.notes.orEmpty()),
        entry.attachmentPaths.joinToString("|") { safeFreeText(it) },
        entry.isResolved?.toString().orEmpty(),
        safeFreeText(detailsJson(entry.details)),
        entry.createdAt?.let(::iso).orEmpty(),
        entry.updatedAt?.let(::iso).orEmpty(),
    ).joinToString(",") { escapeField(it) }

    /** RFC 4180: quote when the field has a comma, quote, CR or LF; double embedded quotes. */
    fun escapeField(value: String): String =
        if (value.any { it == ',' || it == '"' || it == '\r' || it == '\n' }) {
            "\"" + value.replace("\"", "\"\"") + "\""
        } else {
            value
        }

    /** Neutralises spreadsheet formula injection with a leading apostrophe. */
    fun safeFreeText(value: String): String {
        val leading = value.takeWhile { it.isWhitespace() || it.isISOControl() }
        val first = value.drop(leading.length).firstOrNull()
        val hasControlPrefix = leading.any { it == '\t' || it == '\r' || it == '\n' }
        return if (hasControlPrefix || (first != null && first in "=+-@")) "'$value" else value
    }

    /**
     * Plain decimal text for a double, shaped like Swift's `String(Double)` for ordinary magnitudes: `12.5`, `100.0`,
     * `10000000.0` (never `1.0E7`), `0.0005` (never `5.0E-4`). Non-finite values keep their `toString`.
     */
    fun plainNumber(d: Double): String {
        if (!d.isFinite()) return d.toString()
        val plain = BigDecimal(d.toString()).stripTrailingZeros().toPlainString()
        return if ('.' in plain) plain else "$plain.0"
    }

    private fun iso(instant: Instant): String = instant.truncatedTo(ChronoUnit.SECONDS).toString()

    /** Stable (key-sorted) JSON of the details map. */
    fun detailsJson(details: Map<String, Any?>): String =
        if (details.isEmpty()) "{}" else toJson(details).toString()

    private fun toJson(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is JsonElement -> value
        is Boolean -> JsonPrimitive(value)
        // Double.toString switches to exponent form ("1.0E7") that Swift's String(Double) never produces.
        is Double -> if (value.isFinite()) JsonUnquotedLiteral(plainNumber(value)) else JsonPrimitive(value.toString())
        is Float -> toJson(value.toDouble())
        is Number -> JsonPrimitive(value)
        is String -> JsonPrimitive(value)
        is Instant -> JsonPrimitive(iso(value))
        is Map<*, *> -> JsonObject(
            value.entries.sortedBy { it.key.toString() }.associate { it.key.toString() to toJson(it.value) },
        )
        is Iterable<*> -> JsonArray(value.map(::toJson))
        else -> JsonPrimitive(value.toString())
    }
}
