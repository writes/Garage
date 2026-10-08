package com.writes.garage.core.domain

/**
 * What a Log search can match inside an entry's type-specific `details` (iOS `EntryService.filter` parity): the
 * humanized field names and the user-visible values, never storage tokens such as `new_install` or `String(...)`.
 */
object EntrySearch {
    /** `beforeSpecs.frontLeftCamber` -> `before specs front left camber`. */
    fun humanizeKey(key: String): String =
        key.replace('.', ' ').replace('_', ' ')
            .replace(Regex("(?<=[a-z0-9])(?=[A-Z])"), " ")
            .lowercase().trim()

    /** Lower-cased strings a query may match: every field label and every displayable value. */
    fun detailHaystack(details: Map<String, Any?>): List<String> {
        val out = mutableListOf<String>()
        collect("", details, out)
        return out
    }

    private fun collect(prefix: String, map: Map<*, *>, out: MutableList<String>) {
        for ((k, v) in map) {
            val key = if (prefix.isEmpty()) k.toString() else "$prefix.$k"
            out += humanizeKey(key)
            value(v, key, out)
        }
    }

    private fun value(v: Any?, key: String, out: MutableList<String>) {
        when (v) {
            null, is Boolean -> Unit // "true"/"false" are storage tokens, not something a person typed
            is Map<*, *> -> collect(key, v, out)
            is List<*> -> v.forEach { value(it, key, out) }
            is Number -> out += v.toDouble().let { d ->
                if (d == Math.floor(d) && Math.abs(d) < 1e15) d.toLong().toString() else java.math.BigDecimal.valueOf(d).stripTrailingZeros().toPlainString()
            }
            is CharSequence -> out += v.toString().replace('_', ' ').lowercase()
            else -> Unit
        }
    }
}
