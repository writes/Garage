package com.writes.garage.core.notify

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.writes.garage.MainActivity
import com.writes.garage.R
import java.time.Instant

/**
 * Local reminder notifications via [AlarmManager.setAndAllowWhileIdle] (inexact: no exact-alarm permission).
 * The plan is persisted so [BootReceiver] can re-arm it after a reboot without starting the app graph.
 */
object ReminderAlarms {
    const val CHANNEL_ID = "reminders"
    const val EXTRA_KEY = "key"
    const val EXTRA_TITLE = "title"
    const val EXTRA_TEXT = "text"
    private const val PREFS = "garage_reminder_alarms"
    private const val PLAN = "plan"

    /** Replaces everything scheduled before with [plan] (an empty plan cancels all). */
    fun apply(context: Context, plan: List<PlannedAlarm>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = load(prefs.getString(PLAN, null))
        val keep = plan.map { it.key }.toSet()
        previous.filter { it.key !in keep }.forEach { cancel(context, it.key) }
        plan.forEach { schedule(context, it) }
        prefs.edit().putString(PLAN, encode(plan)).apply()
    }

    /** Re-arms the persisted plan (after reboot). Past triggers are dropped. */
    fun rescheduleFromStore(context: Context, now: Instant = Instant.now()) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        load(prefs.getString(PLAN, null)).filter { ReminderPlanner.isFuture(it, now) }.forEach { schedule(context, it) }
    }

    private fun schedule(context: Context, alarm: PlannedAlarm) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        runCatching {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.triggerAt.toEpochMilli(), pendingIntent(context, alarm.key, alarm))
        }
    }

    private fun cancel(context: Context, key: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context, key, null))
    }

    private fun pendingIntent(context: Context, key: String, alarm: PlannedAlarm?): PendingIntent {
        val intent = Intent(context, ReminderAlarmReceiver::class.java).apply {
            data = Uri.parse("garage://reminder/${Uri.encode(key)}")
            if (alarm != null) {
                putExtra(EXTRA_KEY, alarm.key)
                putExtra(EXTRA_TITLE, alarm.title)
                putExtra(EXTRA_TEXT, alarm.text)
            }
        }
        return PendingIntent.getBroadcast(context, key.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Maintenance reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Reminders for upcoming service and maintenance"
            },
        )
    }

    fun notify(context: Context, key: String, title: String, text: String) {
        ensureChannel(context)
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()
        // POST_NOTIFICATIONS is checked above via areNotificationsEnabled().
        @Suppress("MissingPermission")
        nm.notify(key.hashCode(), n)
    }

    internal fun encode(plan: List<PlannedAlarm>): String = plan.joinToString("\n") {
        listOf(it.key, it.reminderId, it.triggerAt.toEpochMilli().toString(), it.title, it.text).joinToString("\t") { f ->
            f.replace('\t', ' ').replace('\n', ' ')
        }
    }

    internal fun load(raw: String?): List<PlannedAlarm> = raw.orEmpty().lines().mapNotNull { line ->
        val p = line.split('\t')
        val at = p.getOrNull(2)?.toLongOrNull() ?: return@mapNotNull null
        if (p.size < 5) return@mapNotNull null
        PlannedAlarm(p[0], p[1], Instant.ofEpochMilli(at), p[3], p[4])
    }
}

class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key = intent.getStringExtra(ReminderAlarms.EXTRA_KEY) ?: return
        val title = intent.getStringExtra(ReminderAlarms.EXTRA_TITLE) ?: return
        val text = intent.getStringExtra(ReminderAlarms.EXTRA_TEXT).orEmpty()
        ReminderAlarms.notify(context, key, title, text)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) ReminderAlarms.rescheduleFromStore(context)
    }
}
