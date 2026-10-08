package com.writes.garage.core.data.firebase

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.entry
import com.writes.garage.TestFixtures.vehicle
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.FuelType
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.UserProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.Date

class FirestoreMappersTest {
    @Test
    fun vehicleRoundTripAndWireFieldNames() {
        val v = vehicle().copy(
            fuelType = FuelType.PREMIUM_93, vin = "WA1CGAFP5FA012345", purchasePrice = 21_500.0, purchaseDate = NOW,
            createdAt = NOW, displayOrder = 2,
        )
        val map = FirestoreMappers.vehicleToMap(v)
        assertEquals("premium_93", map["fuelType"])
        assertEquals("u1", map["userId"])
        assertFalse("nil optionals are absent, exactly like iOS", map.containsKey("licensePlate"))
        assertFalse(map.containsKey("deletedAt"))
        assertEquals(v, FirestoreMappers.vehicleFromMap("v1", map))
    }

    @Test
    fun vehicleWithoutOwnerIsRejectedNotCrashed() {
        assertNull(FirestoreMappers.vehicleFromMap("x", mapOf("make" to "Audi")))
    }

    @Test
    fun updateMapNullsEditableFieldsButNeverSystemFields() {
        val map = FirestoreMappers.vehicleToMap(vehicle(), forUpdate = true)
        assertTrue(map.containsKey("licensePlate") && map["licensePlate"] == null) // -> FieldValue.delete()
        assertTrue(map.containsKey("vin") && map["vin"] == null)
        assertFalse(map.containsKey("createdAt"))
        assertFalse(map.containsKey("deletedAt")) // an edit must not un-delete a tombstoned vehicle
    }

    @Test
    fun countedCreateBindsLastVehicleOpExactly() {
        // The Firestore rule compares lastVehicleOp == {"id": vehicleId, "op": "create"} with no extra keys.
        assertEquals(
            mapOf("lastVehicleOp" to mapOf("id" to "veh-9", "op" to "create")),
            FirestoreMappers.countedCreateUserFields("veh-9"),
        )
        assertEquals(mapOf("deletedAt" to NOW), FirestoreMappers.tombstoneFields(NOW))
    }

    @Test
    fun entryMapMatchesSpecFieldsAndRoundTrips() {
        val e = Entry(
            id = "e1", vehicleId = "v1", userId = "u1", entryType = EntryType.DME_REPORT, entryDate = NOW,
            odometerReading = 12_000, cost = 12.5, isDiy = true, shopName = "S", notes = "n",
            attachmentPaths = listOf("users/u1/entry-attachments/v1/e1/a.jpg"), isResolved = false,
            details = mapOf("k" to 1, "nested" to mapOf("a" to listOf(1, 2)), "dropMe" to null),
            createdAt = NOW, updatedAt = NOW,
        )
        val map = FirestoreMappers.entryToMap(e)
        assertEquals(
            setOf(
                "id", "vehicleId", "userId", "entryType", "entryDate", "odometerReading", "cost", "isDiy", "shopName",
                "notes", "attachmentPaths", "isResolved", "details", "createdAt", "updatedAt",
            ),
            map.keys,
        )
        assertEquals("dme_report", map["entryType"])
        assertEquals(mapOf("k" to 1, "nested" to mapOf("a" to listOf(1, 2))), map["details"])
        assertEquals(e.copy(details = e.details.filterValues { it != null }), FirestoreMappers.entryFromMap("e1", "v1", map))
    }

    @Test
    fun entryAttachmentPathsAlwaysEncodedEvenWhenEmpty() {
        assertEquals(emptyList<String>(), FirestoreMappers.entryToMap(entry("e")).get("attachmentPaths"))
    }

    @Test
    fun firestoreNumbersAndDatesAreCoercedAndBadEntriesSkipped() {
        val raw = mapOf(
            "entryType" to "fuel", "entryDate" to Date(NOW.toEpochMilli()), "odometerReading" to 1234L, "cost" to 40L,
            "userId" to "u1",
        )
        val e = FirestoreMappers.entryFromMap("e1", "vFallback", raw)!!
        assertEquals(1234, e.odometerReading)
        assertEquals(40.0, e.cost!!, 0.0)
        assertEquals("vFallback", e.vehicleId)
        assertEquals(NOW, e.entryDate)
        assertNull("unknown entry type is skipped (forward compat)", FirestoreMappers.entryFromMap("e", "v", raw + ("entryType" to "hovercraft")))
        assertNull("no date, no entry", FirestoreMappers.entryFromMap("e", "v", raw - "entryDate"))
    }

    @Test
    fun reminderRoundTrip() {
        val r = Reminder(
            id = "r1", vehicleId = "v1", title = "Oil", entryType = EntryType.OIL_CHANGE, dueDate = NOW, dueMileage = 50_000,
            repeatIntervalMonths = 6, repeatIntervalMiles = 5_000, notes = "n", isProFeature = true, createdAt = NOW, completedAt = null,
        )
        val map = FirestoreMappers.reminderToMap(r)
        assertEquals("oil_change", map["entryType"])
        assertFalse(map.containsKey("completedAt"))
        assertEquals(r, FirestoreMappers.reminderFromMap("r1", "v1", map))
        // completing a repeating reminder later clears nothing it shouldn't
        val update = FirestoreMappers.reminderToMap(r.copy(completedAt = NOW), forUpdate = true)
        assertEquals(NOW, update["completedAt"])
    }

    @Test
    fun aiConsentIsAnIsoStringLikeIos() {
        assertEquals("", FirestoreMappers.encodeAiConsent(null))
        assertEquals("2026-06-01T12:00:00Z", FirestoreMappers.encodeAiConsent(NOW.plusMillis(999)))
        assertNull(FirestoreMappers.decodeAiConsent(""))
        assertNull(FirestoreMappers.decodeAiConsent(null))
        assertEquals(NOW, FirestoreMappers.decodeAiConsent("2026-06-01T12:00:00Z"))
        assertEquals(mapOf("aiConsentGrantedAt" to "", "updatedAt" to NOW), FirestoreMappers.aiConsentFields(false, NOW))
    }

    @Test
    fun profileFormNeverWritesFieldsOwnedByOtherSurfaces() {
        val p = UserProfile(id = "u1", name = "Ann", themeId = "stale", aiConsentGrantedAt = NOW, analyticsOptOut = false)
        val fields = FirestoreMappers.profileFormFields(p, NOW)
        assertFalse(fields.containsKey("themeID"))
        assertFalse(fields.containsKey("aiConsentGrantedAt"))
        assertEquals("Ann", fields["name"])
        assertEquals("", fields["phone"])
        for (forbidden in listOf("subscription", "vehicleCount", "lastVehicleOp")) assertFalse(fields.containsKey(forbidden))
    }

    @Test
    fun profileFromMapDecodesEmptyStringsAsNullAndDefaultsOptOut() {
        val p = FirestoreMappers.profileFromMap(
            "u1", "a@b.c",
            mapOf("name" to "Ann", "phone" to "", "themeID" to "classic", "aiConsentGrantedAt" to "2026-06-01T12:00:00Z"),
        )
        assertEquals("Ann", p.name)
        assertNull(p.phone)
        assertEquals("classic", p.themeId)
        assertTrue(p.hasAiConsent)
        assertTrue("analytics defaults to opted OUT", p.analyticsOptOut)
    }

    @Test
    fun serverSubscriptionMapDecidesPro() {
        assertTrue(FirestoreMappers.isProFromUserDoc(mapOf("subscription" to mapOf("entitlement" to "pro", "isActive" to true))))
        assertFalse(FirestoreMappers.isProFromUserDoc(mapOf("subscription" to mapOf("entitlement" to "pro", "isActive" to false))))
        assertFalse(FirestoreMappers.isProFromUserDoc(mapOf("subscription" to "garbage")))
        assertFalse(FirestoreMappers.isProFromUserDoc(emptyMap()))
    }

    @Test
    fun instantCoercion() {
        assertEquals(NOW, FirestoreMappers.instant(NOW))
        assertEquals(NOW, FirestoreMappers.instant(NOW.toEpochMilli()))
        assertEquals(NOW, FirestoreMappers.instant("2026-06-01T12:00:00Z"))
        assertNull(FirestoreMappers.instant("not a date"))
        assertEquals(Instant.EPOCH, FirestoreMappers.instant(Date(0)))
    }

    @Test
    fun pathsMatchTheRulesAndIos() {
        assertEquals("vehicles/v1/entries", FirestorePaths.vehicleEntries("v1"))
        assertEquals("vehicles/v1/reminders", FirestorePaths.vehicleReminders("v1"))
        assertEquals("users/u1/entry-attachments/v1/e1/f.jpg", StoragePaths.entryAttachment("u1", "v1", "e1", "f.jpg"))
        assertTrue(StoragePaths.isAllowedContentType("image/jpeg"))
        assertTrue(StoragePaths.isAllowedContentType("application/pdf"))
        assertFalse(StoragePaths.isAllowedContentType("image/"))
        assertFalse(StoragePaths.isAllowedContentType("text/html"))
        assertEquals("pdf", StoragePaths.extensionFor("application/pdf"))
        assertEquals("jpg", StoragePaths.extensionFor("image/jpeg"))
    }
}
