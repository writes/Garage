package com.writes.garage.core.review

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class ReviewPromptTest {
    private val now = Instant.parse("2026-06-01T00:00:00Z")
    private val v = "1.0"

    private fun scored(vararg m: ReviewMoment) = m.fold(ReviewPromptState()) { s, x -> ReviewPromptPolicy.record(s, x) }

    @Test
    fun noSingleFirstRunActionReachesTheThreshold() {
        assertFalse(ReviewPromptPolicy.shouldPrompt(scored(ReviewMoment.ENTRY_LOGGED), v, now))
        assertFalse(ReviewPromptPolicy.shouldPrompt(scored(ReviewMoment.PDF_EXPORTED), v, now))
        assertFalse(ReviewPromptPolicy.shouldPrompt(scored(ReviewMoment.OIL_ANALYSIS_SUCCEEDED, ReviewMoment.ENTRY_LOGGED), v, now))
    }

    @Test
    fun weightedMomentsReachItSooner() {
        assertTrue(ReviewPromptPolicy.shouldPrompt(scored(ReviewMoment.PDF_EXPORTED, ReviewMoment.ENTRY_LOGGED), v, now))
        assertTrue(ReviewPromptPolicy.shouldPrompt(scored(ReviewMoment.PDF_EXPORTED, ReviewMoment.OIL_ANALYSIS_SUCCEEDED), v, now))
        val four = scored(ReviewMoment.ENTRY_LOGGED, ReviewMoment.ENTRY_LOGGED, ReviewMoment.ENTRY_LOGGED, ReviewMoment.ENTRY_LOGGED)
        assertTrue(ReviewPromptPolicy.shouldPrompt(four, v, now))
    }

    @Test
    fun neverTwiceOnTheSameBuildAndHonoursTheCooldown() {
        val eligible = ReviewPromptState(score = 9, lastPromptedVersion = v, lastPromptedAt = now.minus(Duration.ofDays(400)))
        assertFalse(ReviewPromptPolicy.shouldPrompt(eligible, v, now))
        assertTrue(ReviewPromptPolicy.shouldPrompt(eligible.copy(lastPromptedVersion = "0.9"), v, now))
        val recent = eligible.copy(lastPromptedVersion = "0.9", lastPromptedAt = now.minus(Duration.ofDays(30)))
        assertFalse(ReviewPromptPolicy.shouldPrompt(recent, v, now))
        // a stored date in the future (clock change) must not lock the user out
        assertTrue(ReviewPromptPolicy.shouldPrompt(recent.copy(lastPromptedAt = now.plus(Duration.ofDays(5))), v, now))
    }

    @Test
    fun coordinatorBecomesDueThenResetsAfterPrompting() {
        val store = InMemoryReviewStateStore()
        val c = ReviewPromptCoordinator(store, v) { now }
        c.record(ReviewMoment.ENTRY_LOGGED)
        assertFalse(c.due.value)
        c.record(ReviewMoment.PDF_EXPORTED)
        assertTrue(c.due.value)
        c.markPrompted()
        assertFalse(c.due.value)
        assertEquals(0, store.load().score)
        c.record(ReviewMoment.PDF_EXPORTED)
        c.record(ReviewMoment.PDF_EXPORTED)
        assertFalse(c.due.value) // same build: asked already
    }
}
