package com.writes.garage.core.data.firebase

import com.google.firebase.crashlytics.FirebaseCrashlytics
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

/** FCM registration token. iOS does not store a token server-side (no Messaging code), so Android only exposes it. */
class FirebasePushTokenProvider(
    private val messaging: FirebaseMessaging = FirebaseMessaging.getInstance(),
) : PushTokenProvider {
    override suspend fun currentToken(): String? = runCatching { messaging.token.await() }.getOrNull()
}
