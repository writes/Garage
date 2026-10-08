package com.writes.garage.core.data.firebase

import com.google.firebase.Timestamp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class FirestoreValueCodecTest {
    private val at = Instant.parse("2026-06-01T12:00:00.123456789Z")

    @Test
    fun instantsBecomeTimestampsRecursivelyAndBack() {
        val domain = mapOf("when" to at, "list" to listOf(at, 1), "nested" to mapOf("d" to at), "s" to "x")
        val encoded = FirestoreValueCodec.encode(domain) as Map<*, *>
        assertTrue(encoded["when"] is Timestamp)
        assertEquals(Timestamp(at.epochSecond, at.nano), encoded["when"])
        assertEquals(domain, FirestoreValueCodec.decode(encoded))
    }

    @Test
    fun createDropsNullsUpdateKeepsThemForDeletion() {
        val m = mapOf("a" to 1, "b" to null)
        assertEquals(mapOf("a" to 1), FirestoreValueCodec.encodeForCreate(m))
        val upd = FirestoreValueCodec.encodeForUpdate(m)
        assertEquals(setOf("a", "b"), upd.keys)
        assertTrue(upd["b"] is com.google.firebase.firestore.FieldValue)
    }
}
