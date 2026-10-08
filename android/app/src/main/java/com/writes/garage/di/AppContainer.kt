package com.writes.garage.di

import android.app.Application
import android.content.Context
import com.writes.garage.BuildConfig
import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.CrashReporter
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.GoogleSignInProvider
import com.writes.garage.core.data.NoopAnalyticsSink
import com.writes.garage.core.data.NoopCrashReporter
import com.writes.garage.core.data.NoopPushTokenProvider
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.PushTokenProvider
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.data.demo.DemoAuthRepository
import com.writes.garage.core.data.demo.DemoEntryRepository
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.data.demo.DemoPurchaseRepository
import com.writes.garage.core.data.demo.DemoReminderRepository
import com.writes.garage.core.data.demo.DemoStorageRepository
import com.writes.garage.core.data.demo.DemoStore
import com.writes.garage.core.data.demo.DemoVehicleRepository
import com.writes.garage.core.data.firebase.AppCheckInstaller
import com.writes.garage.core.data.firebase.CredentialManagerGoogleSignIn
import com.writes.garage.core.data.firebase.FirebaseAuthRepository
import com.writes.garage.core.data.firebase.FirebaseCrashReporter
import com.writes.garage.core.data.firebase.FirebaseFunctionsGateway
import com.writes.garage.core.data.firebase.FirebasePushTokenProvider
import com.writes.garage.core.data.firebase.FirebaseStorageRepository
import com.writes.garage.core.data.firebase.FirestoreEntryRepository
import com.writes.garage.core.data.firebase.FirestoreProfileRepository
import com.writes.garage.core.data.firebase.FirestoreReminderRepository
import com.writes.garage.core.data.firebase.FirestoreVehicleRepository
import com.writes.garage.core.data.revenuecat.ActivityProvider
import com.writes.garage.core.notify.InMemoryNotificationSettings
import com.writes.garage.core.notify.NotificationSettings
import com.writes.garage.core.notify.PrefsNotificationSettings
import com.writes.garage.core.data.revenuecat.RevenueCatPurchaseRepository
import com.writes.garage.core.data.revenuecat.UnconfiguredPurchaseRepository
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Manual DI root (no Hilt/KSP). Built once in `GarageApplication`. */
interface AppContainer {
    /** true = in-memory Demo mode (no credentials); false = live Firebase/RevenueCat backends. */
    val isDemo: Boolean
    val auth: AuthRepository
    val profile: ProfileRepository
    val vehicles: VehicleRepository
    val entries: EntryRepository
    val reminders: ReminderRepository
    val storage: StorageRepository
    val functions: FunctionsGateway
    val purchases: PurchaseRepository
    val analytics: AnalyticsSink
    val crash: CrashReporter
    val push: PushTokenProvider

    /** Per-device toggle for local reminder notifications. */
    val notifications: NotificationSettings

    /** Non-null only when Google sign-in is configured (live mode with `default_web_client_id`); null hides the button. */
    val googleSignIn: GoogleSignInProvider?
}

/** In-memory, seeded, zero-credential container. */
class DemoAppContainer(store: DemoStore = DemoStore()) : AppContainer {
    override val isDemo: Boolean = true
    override val auth: AuthRepository = DemoAuthRepository(store)
    override val profile: ProfileRepository = DemoProfileRepository(store)
    override val vehicles: VehicleRepository = DemoVehicleRepository(store)
    override val entries: EntryRepository = DemoEntryRepository(store)
    override val reminders: ReminderRepository = DemoReminderRepository(store)
    override val storage: StorageRepository = DemoStorageRepository(store)
    override val functions: FunctionsGateway = DemoFunctionsGateway(store)
    override val purchases: PurchaseRepository = DemoPurchaseRepository(store)
    override val analytics: AnalyticsSink = NoopAnalyticsSink
    override val crash: CrashReporter = NoopCrashReporter
    override val push: PushTokenProvider = NoopPushTokenProvider
    override val notifications: NotificationSettings = InMemoryNotificationSettings()
    override val googleSignIn: GoogleSignInProvider? = null
}

/**
 * Live backend container: Firebase (Auth, Firestore, Storage, Functions, App Check, Crashlytics, Messaging) +
 * RevenueCat. Only constructed when `google-services.json` was present at build time
 * (`BuildConfig.FIREBASE_CONFIGURED`). Without a RevenueCat key everyone is Free and purchases are unavailable.
 */
class FirebaseAppContainer(
    application: Application,
    activities: ActivityProvider,
) : AppContainer {
    override val isDemo: Boolean = false

    init {
        // App Check first: every callable enforces it.
        AppCheckInstaller.install(application)
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val firestore = FirebaseFirestore.getInstance()
    private val prefs = application.getSharedPreferences("garage_prefs", Context.MODE_PRIVATE)

    override val crash: CrashReporter = FirebaseCrashReporter()
    override val push: PushTokenProvider = FirebasePushTokenProvider()
    override val notifications: NotificationSettings = PrefsNotificationSettings(prefs)
    override val analytics: AnalyticsSink = NoopAnalyticsSink
    override val auth: AuthRepository = FirebaseAuthRepository()
    override val googleSignIn: GoogleSignInProvider? = CredentialManagerGoogleSignIn.create(application)
    override val functions: FunctionsGateway = FirebaseFunctionsGateway()
    override val profile: ProfileRepository = FirestoreProfileRepository(firestore, auth)
    override val purchases: PurchaseRepository =
        if (BuildConfig.REVENUECAT_API_KEY.isBlank()) {
            UnconfiguredPurchaseRepository(profile, scope)
        } else {
            RevenueCatPurchaseRepository(application, BuildConfig.REVENUECAT_API_KEY, auth, activities, crash)
        }
    override val vehicles: VehicleRepository = FirestoreVehicleRepository(
        db = firestore,
        auth = auth,
        isPro = { purchases.entitlement.value.isPro },
        purge = { functions.deleteVehicle(it) },
        prefs = prefs,
        crash = crash,
    )
    override val entries: EntryRepository = FirestoreEntryRepository(firestore, auth)
    override val reminders: ReminderRepository = FirestoreReminderRepository(firestore)
    override val storage: StorageRepository = FirebaseStorageRepository(application, auth)

    init {
        // Crash reports carry only the opaque uid.
        scope.launch { auth.currentUser.collect { crash.setUserId(it?.uid) } }
    }
}

fun createAppContainer(application: Application, activities: ActivityProvider): AppContainer =
    if (BuildConfig.FIREBASE_CONFIGURED) FirebaseAppContainer(application, activities) else DemoAppContainer()
