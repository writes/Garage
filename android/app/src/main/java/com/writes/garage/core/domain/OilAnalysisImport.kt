package com.writes.garage.core.domain

/** Maps the `parseOilAnalysis` response onto the OIL_ANALYSIS form fields (nothing is saved; the user reviews and edits). */
object OilAnalysisImport {
    /** Detail keys the callable can return; every one is a field of the OIL_ANALYSIS entry form. */
    val FIELD_KEYS: List<String> = listOf(
        "labName", "milesOnOil", "viscosity", "insolubles",
        "aluminum", "chromium", "iron", "copper", "lead", "tin", "molybdenum", "nickel",
        "manganese", "silver", "titanium", "silicon", "sodium", "potassium",
        "labRecommendation",
    )

    /** Form-string values for the keys present in [result]; absent/blank/unusable values are left out (form keeps its own). */
    fun prefill(result: Map<String, Any?>): Map<String, String> = buildMap {
        for (key in FIELD_KEYS) {
            val text = when (val v = result[key]) {
                null -> null
                is Number -> formatNumber(v.toDouble(), wholeOnly = key == "milesOnOil")
                is String -> v.trim().takeIf { it.isNotEmpty() }
                else -> null
            } ?: continue
            put(key, text)
        }
    }

    /** True when the response carries at least a lab name or a reading (anything else is not an analysis). */
    fun isUsable(prefill: Map<String, String>): Boolean = prefill.keys.any { it != "labRecommendation" }

    private fun formatNumber(d: Double, wholeOnly: Boolean): String? {
        if (!d.isFinite() || d < 0) return null
        return if (wholeOnly || d == Math.rint(d)) d.toLong().toString() else java.math.BigDecimal.valueOf(d).stripTrailingZeros().toPlainString()
    }
}
