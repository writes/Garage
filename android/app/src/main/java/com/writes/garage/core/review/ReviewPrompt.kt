package com.writes.garage.core.review

import java.time.Duration
import java.time.Instant

/** A moment where the user has just received value, so asking for a rating is fair (iOS `ReviewMoment`). */
enum class ReviewMoment(val weight: Int) {
    ENTRY_LOGGED(1),
    OIL_ANALYSIS_SUCCEEDED(2),

    /** The app's peak-value moment. */
    PDF_EXPORTED(3),
}

/** Persisted device-local pacing (no identity; it survives sign-out so a returning user isn't asked twice per build). */
data class ReviewPromptState(
    val score: Int = 0,
    val lastPromptedVersion: String? = null,
    val lastPromptedAt: Instant? = null,
)

/** Pure eligibility rules (port of iOS `ReviewPromptPolicy`). */
object ReviewPromptPolicy {
    /** One export + one entry, one export + one oil analysis, or four entries; no single first-run action reaches it. */
    const val SCORE_REQUIRED = 4

    val COOLDOWN: Duration = Duration.ofDays(120)

    fun shouldPrompt(state: ReviewPromptState, appVersion: String, now: Instant): Boolean {
        if (state.score < SCORE_REQUIRED) return false
        // Never twice on the same build.
        if (state.lastPromptedVersion == appVersion) return false
        val last = state.lastPromptedAt ?: return true
        val elapsed = Duration.between(last, now)
        // A negative elapsed (device clock moved back) must not lock the user out forever.
        return elapsed >= COOLDOWN || elapsed.isNegative
    }

    fun record(state: ReviewPromptState, moment: ReviewMoment): ReviewPromptState =
        state.copy(score = (state.score + moment.weight).coerceAtMost(1_000))

    fun prompted(appVersion: String, now: Instant) =
        ReviewPromptState(score = 0, lastPromptedVersion = appVersion, lastPromptedAt = now)
}

/** Where the VMs report value moments. */
interface ReviewMoments {
    fun record(moment: ReviewMoment)
}

object NoopReviewMoments : ReviewMoments {
    override fun record(moment: ReviewMoment) = Unit
}

interface ReviewStateStore {
    fun load(): ReviewPromptState

    fun save(state: ReviewPromptState)
}

class InMemoryReviewStateStore(private var state: ReviewPromptState = ReviewPromptState()) : ReviewStateStore {
    override fun load() = state

    override fun save(state: ReviewPromptState) {
        this.state = state
    }
}

/**
 * Scores moments and decides when a prompt is [due]. The UI host launches the system flow when it is due AND the
 * screen is a calm one (never first-run, never beside the paywall), then calls [markPrompted].
 */
class ReviewPromptCoordinator(
    private val store: ReviewStateStore,
    private val appVersion: String,
    private val clock: () -> Instant = Instant::now,
) : ReviewMoments {
    private val lock = Any()
    private val _due = kotlinx.coroutines.flow.MutableStateFlow(false)

    /** true while a prompt is eligible and hasn't been shown. */
    val due: kotlinx.coroutines.flow.StateFlow<Boolean> = _due

    override fun record(moment: ReviewMoment) = synchronized(lock) {
        val next = ReviewPromptPolicy.record(store.load(), moment)
        store.save(next)
        _due.value = ReviewPromptPolicy.shouldPrompt(next, appVersion, clock())
    }

    fun markPrompted() = synchronized(lock) {
        store.save(ReviewPromptPolicy.prompted(appVersion, clock()))
        _due.value = false
    }
}
