package com.writes.garage.core.data.firebase

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.FirebaseAppCheck

/**
 * Installs App Check BEFORE any other Firebase product is used (callables enforce it:
 * `enforceAppCheck: true` on receiptQuickAdd, voiceQuickAdd, lookupRecalls, ...). Debug = debug provider,
 * release = Play Integrity (see the `debug` / `release` source sets).
 */
object AppCheckInstaller {
    fun install(context: Context) {
        FirebaseApp.initializeApp(context)
        FirebaseAppCheck.getInstance().installAppCheckProviderFactory(appCheckProviderFactory())
    }
}
