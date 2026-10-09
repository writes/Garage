package com.writes.garage.core.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.retryWhen
import kotlinx.coroutines.launch

/**
 * Drives crash + analytics collection from the stored consent (`users/{uid}.analyticsOptOut`, default opted OUT).
 * Collection is on only while a profile is loaded AND the user has not opted out; signed out, a failed profile
 * load, or an unknown profile all mean off. Sign-out also discards analytics held for the finished identity.
 */
class ConsentCoordinator(
    private val auth: AuthRepository,
    private val profile: ProfileRepository,
    private val crash: CrashReporter,
    private val analytics: AnalyticsSink,
) {
    fun start(scope: CoroutineScope) {
        // Identity: tag crashes with the opaque uid only (the gate holds it back until collection is enabled).
        scope.launch {
            auth.currentUser.distinctUntilChanged { a, b -> a?.uid == b?.uid }.collect { user ->
                crash.setUserId(user?.uid)
                if (user == null) {
                    analytics.setEnabled(false)
                    analytics.discardPending()
                    crash.setEnabled(false)
                }
            }
        }
        scope.launch {
            combine(auth.currentUser, profile.observeProfile().retryWhen { _, attempt ->
                // A listener error (e.g. at sign-out) means consent is unknown: off, back off, resubscribe.
                emit(null)
                delay(minOf(attempt + 1, 30L) * 1000)
                true
            }) { user, p ->
                user != null && p != null && !p.analyticsOptOut
            }.distinctUntilChanged().collect { on ->
                crash.setEnabled(on)
                analytics.setEnabled(on)
            }
        }
    }
}
