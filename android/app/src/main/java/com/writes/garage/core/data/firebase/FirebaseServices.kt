package com.writes.garage.core.data.firebase

import android.os.Bundle
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.writes.garage.core.data.AnalyticsSink
import com.google.firebase.messaging.FirebaseMessaging
import com.writes.garage.core.data.CrashReporter
import com.writes.garage.core.data.PushTokenProvider
import kotlinx.coroutines.tasks.await

class FirebaseCrashReporter(
    private val crashlytics: FirebaseCrashlytics = FirebaseCrashlytics.getInstance(),
) : CrashReporter {
    override fun log(message: String) = crashlytics.log(message)

    override fun record(error: Throwable) = crashlytics.recordException(error)

    override fun setUserId(uid: String?) = crashlytics.setUserId(uid.orEmpty())

    override fun setEnabled(enabled: Boolean) = crashlytics.setCrashlyticsCollectionEnabled(enabled)
}

/** Firebase Analytics behind the consent gate (collection is also disabled in the manifest until opted in). */
class FirebaseAnalyticsSink(private val analytics: FirebaseAnalytics) : AnalyticsSink {
    override fun log(event: String, params: Map<String, Any?>) {
        val bundle = Bundle()
        for ((k, v) in params) {
            when (v) {
                is Int -> bundle.putLong(k, v.toLong())
                is Long -> bundle.putLong(k, v)
                is Double -> bundle.putDouble(k, v)
                is Boolean -> bundle.putLong(k, if (v) 1 else 0)
                is String -> bundle.putString(k, v.take(MAX_STRING))
                else -> Unit
            }
        }
        analytics.logEvent(event, bundle)
    }

    override fun setEnabled(enabled: Boolean) = analytics.setAnalyticsCollectionEnabled(enabled)

    private companion object {
        const val MAX_STRING = 100
    }
}

/** FCM registration token. iOS does not store a token server-side (no Messaging code), so Android only exposes it. */
class FirebasePushTokenProvider(
    private val messaging: FirebaseMessaging = FirebaseMessaging.getInstance(),
) : PushTokenProvider {
    override suspend fun currentToken(): String? = runCatching { messaging.token.await() }.getOrNull()
}
