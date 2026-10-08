package com.writes.garage

import android.app.Application
import com.writes.garage.di.ActivityTracker
import com.writes.garage.di.AppContainer
import com.writes.garage.di.createAppContainer
import com.writes.garage.core.notify.ReminderAlarmSync
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class GarageApplication : Application() {
    lateinit var container: AppContainer
        private set

    private val activities = ActivityTracker()

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(activities)
        // Live (Firebase + RevenueCat) iff google-services.json existed at build time, else Demo mode.
        container = createAppContainer(this, activities)
        // Local reminder notifications follow the user's reminders + the Settings toggle.
        ReminderAlarmSync(this, container.vehicles, container.reminders, container.notifications)
            .start(CoroutineScope(SupervisorJob() + Dispatchers.Default))
    }
}
