package com.writes.garage.di

import android.app.Application
import android.content.Context
import com.writes.garage.BuildConfig
import com.writes.garage.core.data.AnalyticsSink
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.CascadingEntryRepository
import com.writes.garage.core.data.ConsentCoordinator
import com.writes.garage.core.data.ConsentGatedAnalyticsSink
import com.writes.garage.core.data.ConsentGatedCrashReporter
import com.writes.garage.core.data.CrashReporter
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.GoogleSignInProvider
import com.writes.garage.core.data.DetailingRepository
import com.writes.garage.core.data.GalleryRepository
import com.writes.garage.core.data.NoopAnalyticsSink
import com.writes.garage.core.data.PartsRepository
import com.writes.garage.core.data.RecallRepository
import com.writes.garage.core.data.WarrantyRepository
import com.writes.garage.core.data.WearRepository
import com.writes.garage.core.data.demo.DemoRecords
import com.writes.garage.core.data.firebase.FirestoreRecordRepository
import com.writes.garage.core.data.firebase.RecordCodecs
import com.writes.garage.core.data.NoopCrashReporter
import com.writes.garage.core.data.NoopPushTokenProvider
import com.writes.garage.core.data.InMemoryCreditsMarkerStore
import com.writes.garage.core.data.NoopLocalDataWiper
import com.writes.garage.core.data.PrefsCreditsMarkerStore
import com.writes.garage.core.data.ReceiptCreditsCoordinator
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.SessionCleaner
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
import com.writes.garage.core.data.firebase.AndroidLocalDataWiper
import com.writes.garage.core.data.firebase.AppCheckInstaller
import com.writes.garage.core.data.firebase.ProcessRestart
import com.writes.garage.core.data.firebase.CredentialManagerGoogleSignIn
import com.writes.garage.core.data.firebase.FirebaseAuthRepository
import com.writes.garage.core.data.firebase.FirebaseAnalyticsSink
import com.writes.garage.core.data.firebase.FirebaseCrashReporter
import com.writes.garage.core.data.firebase.FirebaseFunctionsGateway
import com.writes.garage.core.data.firebase.FirebasePushTokenProvider
import com.writes.garage.core.data.firebase.FirebaseStorageRepository
import com.writes.garage.core.data.firebase.FirestoreEntryRepository
import com.writes.garage.core.data.firebase.FirestoreProfileRepository
import com.writes.garage.core.data.firebase.FirestoreReminderRepository
import com.writes.garage.core.data.firebase.FirestoreVehicleRepository
import com.writes.garage.core.data.revenuecat.ActivityProvider
import com.writes.garage.core.review.InMemoryReviewStateStore
import com.writes.garage.core.review.NoopReviewLauncher
import com.writes.garage.core.review.PlayReviewLauncher
import com.writes.garage.core.review.PrefsReviewStateStore
import com.writes.garage.core.review.ReviewLauncher
import com.writes.garage.core.review.ReviewPromptCoordinator
import com.writes.garage.core.notify.InMemoryNotificationSettings
import com.writes.garage.core.notify.NotificationSettings
import com.writes.garage.core.notify.PrefsNotificationSettings
import com.writes.garage.core.data.revenuecat.RevenueCatPurchaseRepository
import com.writes.garage.core.data.revenuecat.UnconfiguredPurchaseRepository
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

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

    val gallery: GalleryRepository
    val warranties: WarrantyRepository
    val parts: PartsRepository
    val detailing: DetailingRepository
    val recalls: RecallRepository
    val wear: WearRepository

    /** Buy-and-grant flow for the receipt-credits pack. */
    val receiptCredits: ReceiptCreditsCoordinator

    /** Scores value moments and decides when to ask for a Play Store rating. */
    val reviews: ReviewPromptCoordinator

    /** Shows the Play in-app review flow (no-op in Demo). */
    val reviewLauncher: ReviewLauncher

    /** Ends the session and wipes this device's copy of the account's data. */
    val session: SessionCleaner

    /** Per-device toggle for local reminder notifications. */
    val notifications: NotificationSettings

    /** Non-null only when Google sign-in is configured (live mode with `default_web_client_id`); null hides the button. */
    val googleSignIn: GoogleSignInProvider?
}

/** In-memory, seeded, zero-credential container. */
class DemoAppContainer(store: DemoStore = DemoStore(), application: Application? = null) : AppContainer {
    override val isDemo: Boolean = true
    override val auth: AuthRepository = DemoAuthRepository(store)
    override val profile: ProfileRepository = DemoProfileRepository(store)
    override val vehicles: VehicleRepository = DemoVehicleRepository(store)
    override val reminders: ReminderRepository = DemoReminderRepository(store)
    override val storage: StorageRepository = DemoStorageRepository(store)
    override val functions: FunctionsGateway = DemoFunctionsGateway(store)
    override val purchases: PurchaseRepository = DemoPurchaseRepository(store)
    override val analytics: AnalyticsSink = NoopAnalyticsSink
    override val crash: CrashReporter = NoopCrashReporter
    override val push: PushTokenProvider = NoopPushTokenProvider
    override val gallery: GalleryRepository = DemoRecords.gallery(store)
    override val warranties: WarrantyRepository = DemoRecords.warranties(store)
    override val parts: PartsRepository = DemoRecords.parts(store)
    override val detailing: DetailingRepository = DemoRecords.detailing(store)
    override val recalls: RecallRepository = DemoRecords.recalls(store)
    override val wear: WearRepository = DemoRecords.wear(store)
    override val entries: EntryRepository = CascadingEntryRepository(DemoEntryRepository(store), storage, wear)
    override val notifications: NotificationSettings = InMemoryNotificationSettings()
    override val googleSignIn: GoogleSignInProvider? = null
    override val receiptCredits = ReceiptCreditsCoordinator(purchases, functions, InMemoryCreditsMarkerStore(), pollDelaysMs = listOf(0L))
    override val reviews = ReviewPromptCoordinator(InMemoryReviewStateStore(), BuildConfig.VERSION_NAME)
    override val reviewLauncher: ReviewLauncher = NoopReviewLauncher
    override val session: SessionCleaner = SessionCleaner(
        auth,
        application?.let { AndroidLocalDataWiper(it, null) } ?: NoopLocalDataWiper,
        CoroutineScope(SupervisorJob() + Dispatchers.Default),
    )
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

    override val crash: CrashReporter = ConsentGatedCrashReporter(FirebaseCrashReporter())
    override val push: PushTokenProvider = FirebasePushTokenProvider()
    override val notifications: NotificationSettings = PrefsNotificationSettings(prefs)
    override val analytics: AnalyticsSink =
        ConsentGatedAnalyticsSink(FirebaseAnalyticsSink(FirebaseAnalytics.getInstance(application)))
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
    override val reminders: ReminderRepository = FirestoreReminderRepository(firestore)
    override val storage: StorageRepository = FirebaseStorageRepository(application, auth)
    // Own prefs file on purpose (not wiped with garage_prefs): the marker is bound to the paying uid, so a purchase made
    // before sign-out/deletion is still resolved for that account.
    override val receiptCredits = ReceiptCreditsCoordinator(
        purchases, functions, PrefsCreditsMarkerStore(application.getSharedPreferences("garage_receipt_credits", Context.MODE_PRIVATE)),
        currentUid = { auth.currentUser.value?.uid },
    )
    // Own prefs file on purpose: review pacing is device-local and must survive sign-out / the data wipe.
    override val reviews = ReviewPromptCoordinator(
        PrefsReviewStateStore(application.getSharedPreferences("garage_review", Context.MODE_PRIVATE)), BuildConfig.VERSION_NAME,
    )
    override val reviewLauncher: ReviewLauncher = PlayReviewLauncher()
    override val session: SessionCleaner =
        SessionCleaner(auth, AndroidLocalDataWiper(application, firestore), scope) { ProcessRestart.relaunch(application) }
    override val gallery: GalleryRepository = FirestoreRecordRepository(firestore, RecordCodecs.gallery)
    override val warranties: WarrantyRepository = FirestoreRecordRepository(firestore, RecordCodecs.warranties)
    override val parts: PartsRepository = FirestoreRecordRepository(firestore, RecordCodecs.parts)
    override val detailing: DetailingRepository = FirestoreRecordRepository(firestore, RecordCodecs.detailing)
    override val recalls: RecallRepository = FirestoreRecordRepository(firestore, RecordCodecs.recalls)
    override val wear: WearRepository = FirestoreRecordRepository(firestore, RecordCodecs.wear)
    override val entries: EntryRepository =
        CascadingEntryRepository(FirestoreEntryRepository(firestore, auth), storage, wear) { crash.record(it) }

    init {
        // Crash + analytics collection follow the stored consent (default off); crash reports carry only the opaque uid.
        ConsentCoordinator(auth, profile, crash, analytics).start(scope)
    }
}

fun createAppContainer(application: Application, activities: ActivityProvider): AppContainer =
    if (BuildConfig.FIREBASE_CONFIGURED) FirebaseAppContainer(application, activities) else DemoAppContainer(application = application)
