package com.writes.garage.di

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.writes.garage.core.data.revenuecat.ActivityProvider
import java.lang.ref.WeakReference

/** Tracks the resumed Activity (needed by Play billing and Credential Manager). Holds only a weak reference. */
class ActivityTracker : Application.ActivityLifecycleCallbacks, ActivityProvider {
    private var ref: WeakReference<Activity>? = null

    override fun current(): Activity? = ref?.get()

    override fun onActivityResumed(activity: Activity) {
        ref = WeakReference(activity)
    }

    override fun onActivityPaused(activity: Activity) {
        if (ref?.get() === activity) ref = null
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

    override fun onActivityStarted(activity: Activity) = Unit

    override fun onActivityStopped(activity: Activity) = Unit

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) = Unit
}
