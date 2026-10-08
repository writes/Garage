package com.writes.garage

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import java.io.File

/**
 * Relaunch trampoline (the ProcessPhoenix pattern). It lives in its own `:restart` process so it survives the main
 * process being killed: [com.writes.garage.core.data.firebase.ProcessRestart] starts this, kills the main process, and
 * this activity then starts the real launch intent, which boots a FRESH main process with no stale activity/state.
 * Starting the launcher intent from inside the dying process instead leaves ActivityManager removing it with the process.
 */
class RestartTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        val next = intent?.getParcelableExtra<Intent>(EXTRA_NEXT)
        if (next != null) startActivity(next)
        finish()
        Runtime.getRuntime().exit(0) // this process only exists to bridge the restart
    }

    companion object {
        const val EXTRA_NEXT = "com.writes.garage.extra.NEXT_INTENT"

        /** True inside the `:restart` process; [GarageApplication] skips all heavy init there. */
        fun isRestartProcess(): Boolean = runCatching {
            File("/proc/self/cmdline").readText().trim { it == '\u0000' || it.isWhitespace() }.endsWith(":restart")
        }.getOrDefault(false)
    }
}
