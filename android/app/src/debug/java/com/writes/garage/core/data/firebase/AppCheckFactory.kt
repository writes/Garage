package com.writes.garage.core.data.firebase

import com.google.firebase.appcheck.AppCheckProviderFactory
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory

/**
 * Debug builds attest with the App Check DEBUG provider. On first run it logs a debug token to logcat
 * ("Enter this debug secret into the allow list in the Firebase Console"); register it under
 * App Check -> Apps -> Android (com.writes.garage.debug) -> Manage debug tokens.
 */
internal fun appCheckProviderFactory(): AppCheckProviderFactory = DebugAppCheckProviderFactory.getInstance()
