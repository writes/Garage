package com.writes.garage.core.review

import android.app.Activity
import android.content.SharedPreferences
import com.google.android.play.core.review.ReviewManagerFactory
import java.time.Instant

/** Launches the Play In-App Review flow; the OS decides whether to actually show it (it is quota-limited). */
fun interface ReviewLauncher {
    fun launch(activity: Activity, onFinished: () -> Unit)
}

object NoopReviewLauncher : ReviewLauncher {
    override fun launch(activity: Activity, onFinished: () -> Unit) = onFinished()
}

class PlayReviewLauncher : ReviewLauncher {
    override fun launch(activity: Activity, onFinished: () -> Unit) {
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { request ->
            if (!request.isSuccessful) {
                onFinished()
                return@addOnCompleteListener
            }
            manager.launchReviewFlow(activity, request.result).addOnCompleteListener { onFinished() }
        }
    }
}

class PrefsReviewStateStore(private val prefs: SharedPreferences) : ReviewStateStore {
    override fun load() = ReviewPromptState(
        score = prefs.getInt(SCORE, 0),
        lastPromptedVersion = prefs.getString(VERSION, null),
        lastPromptedAt = prefs.getLong(AT, -1L).takeIf { it >= 0 }?.let(Instant::ofEpochMilli),
    )

    override fun save(state: ReviewPromptState) {
        prefs.edit()
            .putInt(SCORE, state.score)
            .putString(VERSION, state.lastPromptedVersion)
            .putLong(AT, state.lastPromptedAt?.toEpochMilli() ?: -1L)
            .apply()
    }

    private companion object {
        const val SCORE = "review_score"
        const val VERSION = "review_last_version"
        const val AT = "review_last_at"
    }
}
