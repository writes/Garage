package com.writes.garage.core.data

/** Non-fatal error + breadcrumb reporting (Crashlytics in live mode). Never receives PII beyond the opaque uid. */
interface CrashReporter {
    fun log(message: String)

    fun record(error: Throwable)

    fun setUserId(uid: String?)

    fun setEnabled(enabled: Boolean)
}

/**
 * Collection OFF until the signed-in user's stored opt-in (iOS parity: `CrashReportingService`). While disabled,
 * log/record/setUserId reach nothing; the uid is remembered and applied only once collection is enabled, and cleared
 * on disable.
 */
class ConsentGatedCrashReporter(private val delegate: CrashReporter) : CrashReporter {
    @Volatile private var enabled = false
    @Volatile private var uid: String? = null

    override fun log(message: String) {
        if (enabled) delegate.log(message)
    }

    override fun record(error: Throwable) {
        if (enabled) delegate.record(error)
    }

    override fun setUserId(uid: String?) {
        this.uid = uid
        if (enabled) delegate.setUserId(uid)
    }

    override fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
        delegate.setEnabled(enabled)
        delegate.setUserId(if (enabled) uid else null)
    }
}

object NoopCrashReporter : CrashReporter {
    override fun log(message: String) = Unit

    override fun record(error: Throwable) = Unit

    override fun setUserId(uid: String?) = Unit

    override fun setEnabled(enabled: Boolean) = Unit
}

/** Push token access (FCM in live mode). iOS does not persist an FCM token server-side, so neither does Android. */
interface PushTokenProvider {
    suspend fun currentToken(): String?
}

object NoopPushTokenProvider : PushTokenProvider {
    override suspend fun currentToken(): String? = null
}

/**
 * Starts the Google sign-in UI (Credential Manager) and returns a Google ID token for
 * [AuthRepository.signInWithGoogle]. Null provider = feature hidden (no web client id / Demo mode).
 */
interface GoogleSignInProvider {
    /** [activityContext] must be an Activity (Credential Manager shows a bottom sheet). */
    suspend fun requestIdToken(activityContext: android.content.Context): String
}
