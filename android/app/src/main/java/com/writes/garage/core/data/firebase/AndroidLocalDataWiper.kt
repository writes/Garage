package com.writes.garage.core.data.firebase

import android.content.Context
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import com.google.firebase.firestore.FirebaseFirestore
import com.writes.garage.core.data.LocalDataWiper
import com.writes.garage.core.data.LocalFiles
import com.writes.garage.core.notify.ReminderAlarms
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File

/**
 * Live-mode wipe. Firestore's persistent cache can only be cleared on a terminated instance, and a terminated
 * instance is unusable, so [needsRestart] tells the caller to relaunch the process afterwards.
 * Every step is best-effort and independent: one failure never stops the rest.
 */
class AndroidLocalDataWiper(
    private val context: Context,
    private val firestore: FirebaseFirestore?,
    private val prefNames: List<String> = listOf("garage_prefs", "garage_reminder_alarms"),
) : LocalDataWiper {
    override val needsRestart: Boolean get() = firestore != null

    private companion object {
        const val CREDENTIAL_CLEAR_TIMEOUT_MS = 5_000L
    }

    override suspend fun wipe() {
        withContext(Dispatchers.IO) {
            runCatching { LocalFiles.clearDirectory(File(context.cacheDir, "exports")) }
            runCatching { LocalFiles.clearDirectory(File(context.cacheDir, "capture")) }
        }
        runCatching { ReminderAlarms.apply(context, emptyList()) }
        prefNames.forEach { name -> runCatching { context.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().commit() } }
        // A credential provider that never answers must not hold up the rest of the wipe (or the relaunch after it).
        runCatching {
            withTimeoutOrNull(CREDENTIAL_CLEAR_TIMEOUT_MS) {
                CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest())
            }
        }
        firestore?.let { db ->
            runCatching {
                db.terminate().await()
                db.clearPersistence().await()
            }
        }
    }
}

/**
 * Relaunches the app in a fresh process (needed after Firestore was terminated to clear its cache). Goes through a
 * trampoline activity in a separate process so the new task is started by a process that outlives this one.
 */
object ProcessRestart {
    fun relaunch(context: Context) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (launch != null) {
            val trampoline = android.content.Intent(context, com.writes.garage.RestartTrampolineActivity::class.java)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(com.writes.garage.RestartTrampolineActivity.EXTRA_NEXT, launch)
            context.startActivity(trampoline)
        }
        // Give the binder call a beat to leave this process, then die so the next launch gets a clean main process.
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ Runtime.getRuntime().exit(0) }, RESTART_DELAY_MS)
    }

    private const val RESTART_DELAY_MS = 50L
}
