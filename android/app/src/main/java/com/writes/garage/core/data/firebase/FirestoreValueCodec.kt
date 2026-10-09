package com.writes.garage.core.data.firebase

import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import java.time.Instant

/** SDK boundary: domain [Instant] <-> Firestore [Timestamp], recursively through maps and lists. */
object FirestoreValueCodec {
    fun decode(v: Any?): Any? = when (v) {
        is Timestamp -> Instant.ofEpochSecond(v.seconds, v.nanoseconds.toLong())
        is Map<*, *> -> v.entries.associate { it.key.toString() to decode(it.value) }
        is List<*> -> v.map(::decode)
        else -> v
    }

    fun decodeMap(m: Map<String, Any?>?): Map<String, Any?> =
        m?.entries?.associate { it.key to decode(it.value) } ?: emptyMap()

    fun encode(v: Any?): Any? = when (v) {
        is Instant -> Timestamp(v.epochSecond, v.nano)
        is Map<*, *> -> v.entries.associate { it.key.toString() to encode(it.value) }
        is List<*> -> v.map(::encode)
        else -> v
    }

    /** Top-level null -> `FieldValue.delete()` (only valid in merge-sets/updates). Everything else is [encode]d. */
    fun encodeForUpdate(m: Map<String, Any?>): Map<String, Any?> =
        m.entries.associate { (k, v) -> k to (if (v == null) FieldValue.delete() else encode(v)) }

    fun encodeForCreate(m: Map<String, Any?>): Map<String, Any?> =
        m.entries.filter { it.value != null }.associate { it.key to encode(it.value) }
}
