package com.writes.garage.core.data

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.writes.garage.core.data.firebase.AndroidLocalDataWiper
import com.writes.garage.core.notify.PlannedAlarm
import com.writes.garage.core.notify.PrefsNotificationSettings
import com.writes.garage.core.notify.ReminderAlarms
import com.writes.garage.core.review.PrefsReviewStateStore
import com.writes.garage.core.review.ReviewPromptState
import com.writes.garage.feature.shared.CaptureFiles
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
class LocalDataRobolectricTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    fun resetFileProviderCache() {
        val f = androidx.core.content.FileProvider::class.java.getDeclaredField("sCache")
        f.isAccessible = true
        (f.get(null) as MutableMap<*, *>).clear()
    }

    private fun capture(name: String, ageMs: Long = 0): File {
        val dir = File(context.cacheDir, "capture").apply { mkdirs() }
        return File(dir, name).apply {
            writeText("x")
            if (ageMs > 0) setLastModified(System.currentTimeMillis() - ageMs)
        }
    }

    // ---- CaptureFiles

    @Test
    fun newCaptureUriIsOurFileProviderAndSweepsStaleShots() {
        val stale = capture("old.jpg", ageMs = 2 * 60 * 60 * 1000L)
        val fresh = capture("fresh.jpg", ageMs = 5 * 60 * 1000L)
        val uri = CaptureFiles.newUri(context, "receipt")
        assertEquals("${context.packageName}.fileprovider", uri.authority)
        assertTrue(uri.lastPathSegment!!.startsWith("receipt-") && uri.lastPathSegment!!.endsWith(".jpg"))
        assertFalse("captures older than an hour are deleted", stale.exists())
        assertTrue(fresh.exists())
    }

    @Test
    fun releaseDeletesOnlyOurOwnCaptureFiles() {
        val mine = capture("mine.jpg")
        val other = File(context.cacheDir, "exports").apply { mkdirs() }.let { File(it, "mine.jpg").apply { writeText("keep") } }
        CaptureFiles.release(context, "content://${context.packageName}.fileprovider/capture/mine.jpg")
        assertFalse(mine.exists())
        assertTrue("a file in another folder with the same name is untouched", other.exists())

        val keep = capture("keep.jpg")
        CaptureFiles.release(context, "content://com.someone.else.fileprovider/capture/keep.jpg")
        CaptureFiles.release(context, "content://media/external/images/1")
        CaptureFiles.release(context, "content://${context.packageName}.fileprovider/capture/..")
        assertTrue("foreign authorities are never touched", keep.exists())
    }

    // ---- AndroidLocalDataWiper

    @Test
    fun wipeRemovesExportsCapturesPrefsAndTheAlarmPlan() = runTest {
        File(context.cacheDir, "exports").apply { mkdirs() }.let { File(it, "dossier.pdf").writeText("pii") }
        capture("shot.jpg")
        context.getSharedPreferences("garage_prefs", Context.MODE_PRIVATE).edit().putString("active_vehicle", "v1").commit()
        context.getSharedPreferences("other_prefs", Context.MODE_PRIVATE).edit().putString("keep", "me").commit()
        ReminderAlarms.apply(context, listOf(PlannedAlarm("r:0", "r", Instant.now().plusSeconds(3600), "t", "x")))
        assertEquals(1, shadowOf(context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager).scheduledAlarms.size)

        val wiper = AndroidLocalDataWiper(context, firestore = null)
        assertFalse("no Firestore instance -> no relaunch needed", wiper.needsRestart)
        wiper.wipe()

        assertTrue(File(context.cacheDir, "exports").listFiles().orEmpty().isEmpty())
        assertTrue(File(context.cacheDir, "capture").listFiles().orEmpty().isEmpty())
        assertNull(context.getSharedPreferences("garage_prefs", Context.MODE_PRIVATE).getString("active_vehicle", null))
        assertTrue(context.getSharedPreferences("garage_reminder_alarms", Context.MODE_PRIVATE).all.let { it["plan"] in listOf(null, "") })
        assertTrue("every scheduled reminder alarm is cancelled", shadowOf(context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager).scheduledAlarms.isEmpty())
        assertEquals("prefs the wiper does not own survive", "me", context.getSharedPreferences("other_prefs", Context.MODE_PRIVATE).getString("keep", null))
    }

    @Test
    fun wipeWithNothingToWipeDoesNotThrow() = runTest {
        AndroidLocalDataWiper(context, firestore = null).wipe()
    }

    // ---- preference-backed stores

    @Test
    fun reviewStateRoundTripsAndDefaultsWhenEmpty() {
        val store = PrefsReviewStateStore(context.getSharedPreferences("review_test", Context.MODE_PRIVATE))
        val empty = store.load()
        assertEquals(0, empty.score)
        assertNull(empty.lastPromptedVersion)
        assertNull(empty.lastPromptedAt)
        val state = ReviewPromptState(score = 7, lastPromptedVersion = "1.2.3", lastPromptedAt = Instant.parse("2026-05-01T10:00:00Z"))
        store.save(state)
        assertEquals(state, PrefsReviewStateStore(context.getSharedPreferences("review_test", Context.MODE_PRIVATE)).load())
        store.save(ReviewPromptState(score = 8))
        assertNull(store.load().lastPromptedAt)
    }

    @Test
    fun notificationSettingPersistsAcrossInstances() {
        val prefs = context.getSharedPreferences("notif_test", Context.MODE_PRIVATE)
        val a = PrefsNotificationSettings(prefs)
        assertFalse("off by default", a.enabled.value)
        a.setEnabled(true)
        assertTrue(a.enabled.value)
        assertTrue(PrefsNotificationSettings(prefs).enabled.value)
        a.setEnabled(false)
        assertFalse(PrefsNotificationSettings(prefs).enabled.value)
    }

    @Test
    fun uriParsingOfOurAuthorityIsStable() {
        assertEquals("shot.jpg", Uri.parse("content://x.fileprovider/capture/shot.jpg").lastPathSegment)
    }
}
