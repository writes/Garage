package com.writes.garage.core.domain

/** Reads loosely-typed `details` map values (Firestore numbers arrive as Long/Double). */
internal fun Any?.asDouble(): Double? = when (this) {
    is Number -> toDouble()
    is String -> toDoubleOrNull()
    else -> null
}
