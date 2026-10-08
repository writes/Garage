package com.writes.garage.core.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async

/**
 * Ends the signed-in session and then removes the account's data from the device. Runs on an application-level
 * scope on purpose: signing out swaps the whole UI to the auth screen, which cancels screen-scoped coroutines, and
 * the wipe must still finish.
 */
class SessionCleaner(
    private val auth: AuthRepository,
    private val wiper: LocalDataWiper,
    private val scope: CoroutineScope,
    /** Relaunches the process after a wipe that terminated Firestore (live mode only). */
    private val restart: () -> Unit = {},
) {
    /**
     * [beforeSignOut] runs first (e.g. the server-side account delete); if it or the sign-out throws, nothing is wiped
     * and the failure is delivered to whoever awaits the result.
     */
    fun endSession(beforeSignOut: suspend () -> Unit = {}): Deferred<Unit> = scope.async {
        beforeSignOut()
        auth.signOut()
        wiper.wipe()
        if (wiper.needsRestart) restart()
    }
}
