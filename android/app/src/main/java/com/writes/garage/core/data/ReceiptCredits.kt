package com.writes.garage.core.data

import android.content.SharedPreferences
import com.writes.garage.core.model.CreditsPurchaseResult
import com.writes.garage.core.model.ReceiptQuota
import kotlinx.coroutines.delay

/**
 * Remembers an unresolved credit purchase, bound to the paying uid, so a process death between "store charged" and
 * "server granted" resumes the grant check instead of losing it (port of iOS `ReceiptCreditsMarkerStore`).
 */
interface ReceiptCreditsMarkerStore {
    fun save(uid: String, transactionId: String)

    fun pending(uid: String): String?

    fun resolve(uid: String, transactionId: String)
}

class InMemoryCreditsMarkerStore : ReceiptCreditsMarkerStore {
    private val map = mutableMapOf<String, String>()

    override fun save(uid: String, transactionId: String) {
        map[uid] = transactionId
    }

    override fun pending(uid: String): String? = map[uid]

    override fun resolve(uid: String, transactionId: String) {
        if (map[uid] == transactionId) map.remove(uid)
    }
}

class PrefsCreditsMarkerStore(private val prefs: SharedPreferences) : ReceiptCreditsMarkerStore {
    override fun save(uid: String, transactionId: String) {
        prefs.edit().putString(key(uid), transactionId).apply()
    }

    override fun pending(uid: String): String? = prefs.getString(key(uid), null)

    override fun resolve(uid: String, transactionId: String) {
        if (pending(uid) == transactionId) prefs.edit().remove(key(uid)).apply()
    }

    private fun key(uid: String) = "credits_marker_$uid"
}

/** Where a credits purchase ended up. */
sealed interface CreditsOutcome {
    /** The server granted the credits; [quota] is the fresh snapshot. */
    data class Granted(val quota: ReceiptQuota) : CreditsOutcome

    /** The purchase was refunded; credits were not (or no longer) granted. */
    data class Refunded(val quota: ReceiptQuota) : CreditsOutcome

    /** Charged, but the grant hasn't shown up yet. The marker stays; the next screen open resumes the check. */
    data object Delayed : CreditsOutcome

    data object Cancelled : CreditsOutcome

    data object Pending : CreditsOutcome

    data object Unavailable : CreditsOutcome

    data class Failed(val message: String) : CreditsOutcome

    /** Refused BEFORE the store was touched: the store identity is anonymous or isn't the signed-in uid. No money moved. */
    data object IdentityMismatch : CreditsOutcome

    /**
     * The store charged, but the identity changed mid-purchase. The marker stays bound to the uid that paid, so that
     * account recovers the grant the next time it opens the screen; the current user's quota is not polled.
     */
    data object IdentityChangedAfterPurchase : CreditsOutcome
}

/**
 * Buy the +10 receipt-credits pack, then wait for the server to grant it: persist a marker, poll
 * `receiptQuotaStatus {transactionId}` on a backoff (RevenueCat's webhook lands in 5-60 s), then ask the server to
 * reconcile directly. The client never grants credits itself.
 */
class ReceiptCreditsCoordinator(
    private val purchases: PurchaseRepository,
    private val functions: FunctionsGateway,
    private val markers: ReceiptCreditsMarkerStore,
    private val pollDelaysMs: List<Long> = POLL_DELAYS_MS,
    /** The signed-in Firebase uid right now; null skips the Firebase half of the identity re-check. */
    private val currentUid: (() -> String?)? = null,
    private val sleep: suspend (Long) -> Unit = { delay(it) },
) {
    private var purchasing = false

    /** Store identity is bound (not anonymous) to [uid], and the Firebase user hasn't changed under us. */
    private fun identityHolds(uid: String): Boolean =
        !purchases.isAnonymous &&
            purchases.appUserID.let { it == null || it == uid } &&
            (currentUid == null || currentUid.invoke() == uid)

    suspend fun purchase(uid: String, onWaitingForGrant: () -> Unit = {}): CreditsOutcome {
        if (purchasing) return CreditsOutcome.Cancelled // a second tap while the store sheet is up is dropped
        // An anonymous/divergent RevenueCat identity would charge a user the webhook can never credit.
        if (!identityHolds(uid)) return CreditsOutcome.IdentityMismatch
        purchasing = true
        try {
            return purchaseOnce(uid, onWaitingForGrant)
        } finally {
            purchasing = false
        }
    }

    private suspend fun purchaseOnce(uid: String, onWaitingForGrant: () -> Unit): CreditsOutcome =
        when (val r = purchases.purchaseReceiptCredits()) {
            is CreditsPurchaseResult.Completed -> {
                // Persist BEFORE the post-check and polling: money has moved, so a killed process must be able to
                // resume, and the marker stays bound to the uid that paid even if identity diverged mid-purchase.
                markers.save(uid, r.transactionId)
                if (!identityHolds(uid)) {
                    CreditsOutcome.IdentityChangedAfterPurchase
                } else {
                    onWaitingForGrant()
                    awaitGrant(uid, r.transactionId)
                }
            }
            CreditsPurchaseResult.Cancelled -> CreditsOutcome.Cancelled
            CreditsPurchaseResult.Pending -> CreditsOutcome.Pending
            CreditsPurchaseResult.Unavailable -> CreditsOutcome.Unavailable
            is CreditsPurchaseResult.Failed -> CreditsOutcome.Failed(r.message)
        }

    /** Resumes an unresolved purchase for [uid], if any. Null when there is nothing to resume. */
    suspend fun resume(uid: String): CreditsOutcome? = markers.pending(uid)?.let { awaitGrant(uid, it) }

    private suspend fun awaitGrant(uid: String, transactionId: String): CreditsOutcome {
        for (wait in pollDelaysMs) {
            sleep(wait)
            terminal(uid, transactionId, runCatching { functions.receiptQuotaStatus(transactionId) }.getOrNull())?.let { return it }
        }
        // Only a reconcile that SUCCEEDED and still found nothing is a real miss; thrown errors stay retryable.
        terminal(uid, transactionId, runCatching { functions.reconcileReceiptCreditPurchase(transactionId) }.getOrNull())?.let { return it }
        return CreditsOutcome.Delayed
    }

    private fun terminal(uid: String, transactionId: String, quota: ReceiptQuota?): CreditsOutcome? = when (quota?.transactionState) {
        "granted" -> CreditsOutcome.Granted(quota).also { markers.resolve(uid, transactionId) }
        "refunded" -> CreditsOutcome.Refunded(quota).also { markers.resolve(uid, transactionId) }
        else -> null
    }

    companion object {
        /** 2/4/8/16/30 s, roughly RevenueCat's documented webhook delivery window. */
        val POLL_DELAYS_MS = listOf(2_000L, 4_000L, 8_000L, 16_000L, 30_000L)
    }
}
