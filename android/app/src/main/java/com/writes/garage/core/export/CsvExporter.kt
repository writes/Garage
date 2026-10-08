package com.writes.garage.core.export

import com.writes.garage.core.model.Entry
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Raw entry export, schema-compatible with iOS `CSVExportService` (schema_version 2): RFC 4180 quoting,
 * CRLF line endings, and a spreadsheet-formula guard on free text (a leading `= + - @` or control
 * whitespace gets a `'` prefix so Excel/Sheets never evaluate user text).
 */
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
        entry.cost?.toString().orEmpty(),
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

    private fun iso(instant: Instant): String = instant.truncatedTo(ChronoUnit.SECONDS).toString()

    /** Stable (key-sorted) JSON of the details map. */
    fun detailsJson(details: Map<String, Any?>): String =
        if (details.isEmpty()) "{}" else toJson(details).toString()

    private fun toJson(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is JsonElement -> value
        is Boolean -> JsonPrimitive(value)
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
