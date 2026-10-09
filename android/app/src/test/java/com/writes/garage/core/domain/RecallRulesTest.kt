package com.writes.garage.core.domain

import com.writes.garage.TestFixtures.NOW
import com.writes.garage.TestFixtures.vehicle
import com.writes.garage.core.data.firebase.FunctionsMappers
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RecallRulesTest {
    private fun recall(id: String, campaign: String?, notes: String? = null, status: RecallStatus = RecallStatus.OUTSTANDING) =
        Recall(id = id, vehicleId = "v1", campaignNumber = campaign, title = "t$id", status = status, notes = notes)

    @Test
    fun safetyAdvisoriesAreDetectedFromTheMapperNotes() {
        val notes = FunctionsMappers.recallNotes("Dealer will replace", parkIt = true, parkOutside = false)
        val parkOnly = FunctionsMappers.recallNotes(null, parkIt = false, parkOutside = true)
        assertTrue(RecallRules.isDoNotDrive(recall("a", "1", notes)))
        assertFalse(RecallRules.isParkOutside(recall("a", "1", notes)))
        assertTrue(RecallRules.isParkOutside(recall("b", "2", parkOnly)))
    }

    @Test
    fun urgentOnlyCountsOutstandingRecalls() {
        val notes = FunctionsMappers.recallNotes(null, parkIt = true, parkOutside = false)
        val open = recall("a", "1", notes)
        val done = recall("b", "2", notes, RecallStatus.COMPLETED)
        assertEquals(listOf(open), RecallRules.urgent(listOf(open, done)))
        assertEquals(1, RecallRules.outstandingCount(listOf(open, done, recall("c", "3", status = RecallStatus.NOT_APPLICABLE))))
    }

    @Test
    fun orderedPutsUrgentFirstThenOutstanding() {
        val notes = FunctionsMappers.recallNotes(null, parkIt = true, parkOutside = false)
        val urgent = recall("u", "1", notes)
        val plain = recall("p", "2")
        val done = recall("d", "3", status = RecallStatus.COMPLETED)
        assertEquals(listOf("u", "p", "d"), RecallRules.ordered(listOf(done, plain, urgent)).map { it.id })
    }

    @Test
    fun newRecallsSkipsKnownCampaignsSoCompletedOnesAreNeverReset() {
        val known = listOf(recall("x", "15V-123", status = RecallStatus.COMPLETED))
        val fetched = listOf(recall("15V-123", "15V-123"), recall("16V-9", "16V-9"), recall("dup", " 16v-9 "))
        val fresh = RecallRules.newRecalls(known, fetched, NOW)
        assertEquals(listOf("16V-9"), fresh.map { it.campaignNumber })
        assertEquals("", fresh.single().id) // the repository assigns the id
        assertEquals(NOW, fresh.single().createdAt)
    }

    @Test
    fun recallsWithoutACampaignNumberDedupeOnTitleComponentAndDate() {
        val stored = recall("x", null, status = RecallStatus.COMPLETED).copy(title = "Airbag", componentAffected = "Air Bags")
        val again = recall("y", null).copy(title = " airbag ", componentAffected = "air bags")
        val different = recall("z", null).copy(title = "Brakes")
        val fresh = RecallRules.newRecalls(listOf(stored), listOf(again, different, different), NOW)
        assertEquals(listOf("Brakes"), fresh.map { it.title })
    }

    @Test
    fun markCompletedKeepsShopOdometerAndDate() {
        val done = RecallRules.markCompleted(recall("a", "1"), "  Dealer ", 82_000, NOW)
        assertEquals(RecallStatus.COMPLETED, done.status)
        assertEquals("Dealer", done.completedShop)
        assertEquals(82_000, done.completedOdometer)
        assertEquals(NOW, done.completedDate)
        assertNull(RecallRules.markCompleted(recall("a", "1"), " ", null, NOW).completedShop)
    }

    @Test
    fun summaryPluralises() {
        assertEquals("Checked 2015 Audi SQ5 - 1 recall on file.", RecallRules.summary(vehicle(), 1))
        assertEquals("Checked 2015 Audi SQ5 - 0 recalls on file.", RecallRules.summary(vehicle(), 0))
    }
}
