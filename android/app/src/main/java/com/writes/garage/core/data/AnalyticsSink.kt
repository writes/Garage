package com.writes.garage.core.data

interface AnalyticsSink {
    /** Event names and parameter keys follow the iOS contract (`docs/developer/ANALYTICS_CONTRACT.md`); never PII. */
    fun log(event: String, params: Map<String, Any?> = emptyMap())

    fun setEnabled(enabled: Boolean)

    /** Drops events held while consent was unknown. Called when the identity ends (sign-out), never on a plain disable. */
    fun discardPending() = Unit
}

/** Drops everything. */
object NoopAnalyticsSink : AnalyticsSink {
    override fun log(event: String, params: Map<String, Any?>) = Unit

    override fun setEnabled(enabled: Boolean) = Unit
}

/**
 * Consent gate in front of a real sink (port of iOS `AnalyticsConsentGate`). Consent is only knowable after sign-in
 * loads the profile, so events fired earlier (the sign-in funnel) are HELD, bounded, and released only by an
 * affirmative [setEnabled] (true). `setEnabled(false)` means "consent unknown" and keeps the buffer; an identity
 * change must call [discardPending] so one account's events can never flush under another's consent.
 */
class ConsentGatedAnalyticsSink(
    private val delegate: AnalyticsSink,
    private val limit: Int = DEFAULT_LIMIT,
) : AnalyticsSink {
    private data class Held(val event: String, val params: Map<String, Any?>)

    private val lock = Any()
    private var enabled = false
    private val pending = ArrayDeque<Held>()

    val pendingCount: Int get() = synchronized(lock) { pending.size }

    override fun log(event: String, params: Map<String, Any?>) {
        val send = synchronized(lock) {
            if (!enabled) {
                pending.addLast(Held(event, params))
                while (pending.size > limit) pending.removeFirst()
                false
            } else {
                true
            }
        }
        if (send) delegate.log(event, params)
    }

    override fun setEnabled(enabled: Boolean) {
        val released = synchronized(lock) {
            this.enabled = enabled
            if (enabled) pending.toList().also { pending.clear() } else emptyList()
        }
        delegate.setEnabled(enabled)
        released.forEach { delegate.log(it.event, it.params) }
    }

    override fun discardPending() = synchronized(lock) { pending.clear() }

    companion object {
        const val DEFAULT_LIMIT = 32
    }
}

/** Event names (subset of the frozen iOS contract) so call sites don't scatter string literals. */
object AnalyticsEvents {
    const val SCHEMA_VERSION = "schema_version"
    const val SIGN_IN_COMPLETED = "sign_in_completed"
    const val SIGN_IN_FAILED = "sign_in_failed"
    const val ENTRY_SAVED = "entry_saved"
    const val FIRST_ENTRY_ADDED = "first_entry_added"
    const val ENTRY_DELETED = "entry_deleted"
    const val RECEIPT_ENTRY_CONFIRMED = "receipt_entry_confirmed"
    const val VOICE_ENTRY_CONFIRMED = "voice_entry_confirmed"
    const val EXPORT_PDF = "export_pdf"
    const val EXPORT_CSV = "export_csv"
    const val PAYWALL_VIEWED = "paywall_viewed"
    const val PURCHASE_COMPLETED = "purchase_completed"
    const val OIL_ANALYSIS_SUCCEEDED = "oil_analysis_succeeded"
    const val REMINDER_CREATED = "reminder_created"
    const val REMINDER_COMPLETED = "reminder_completed"
    const val REMINDER_DELETED = "reminder_deleted"

    /** Params every event carries (the frozen schema version). */
    fun params(vararg extra: Pair<String, Any?>): Map<String, Any?> = mapOf(SCHEMA_VERSION to 1) + extra
}
