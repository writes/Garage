package com.writes.garage.core.data.revenuecat

import android.app.Application
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitLogOut
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.CrashReporter
import com.writes.garage.core.data.NoopCrashReporter
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.PaywallPackage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

/** Supplies the foreground Activity the Play billing flow needs. */
fun interface ActivityProvider {
    fun current(): android.app.Activity?
}

/**
 * RevenueCat-backed purchases. The Firebase uid is the RevenueCat `appUserID` (so the server webhook can write
 * `users/{uid}.subscription`). The entitlement id is [RevenueCatMapper.ENTITLEMENT_ID].
 */
class RevenueCatPurchaseRepository(
    application: Application,
    apiKey: String,
    private val auth: AuthRepository,
    private val activity: ActivityProvider,
    private val crash: CrashReporter = NoopCrashReporter,
) : PurchaseRepository {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _entitlement = MutableStateFlow(Entitlement.FREE)
    override val entitlement: StateFlow<Entitlement> = _entitlement.asStateFlow()
    private var packages: Map<String, Package> = emptyMap()

    init {
        if (!Purchases.isConfigured) {
            Purchases.configure(PurchasesConfiguration.Builder(application, apiKey).build())
        }
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        // Bind the RevenueCat identity to the Firebase uid for the life of the session.
        scope.launch {
            auth.currentUser.collect { user ->
                runCatching {
                    if (user != null && !user.isDemo) {
                        apply(Purchases.sharedInstance.awaitLogIn(user.uid).customerInfo)
                    } else if (!Purchases.sharedInstance.isAnonymous) {
                        apply(Purchases.sharedInstance.awaitLogOut())
                    } else {
                        _entitlement.value = Entitlement.FREE
                    }
                }.onFailure { crash.record(it) }
            }
        }
    }

    private fun apply(info: CustomerInfo) {
        val e = info.entitlements[RevenueCatMapper.ENTITLEMENT_ID]
        _entitlement.value = RevenueCatMapper.entitlement(
            isActive = e?.isActive == true,
            productId = e?.productIdentifier,
            expiresAtMillis = e?.expirationDate?.time,
            willRenew = e?.willRenew == true,
        )
    }

    override suspend fun loadPackages(): List<PaywallPackage> {
        val offering = Purchases.sharedInstance.awaitOfferings().current ?: return emptyList()
        packages = offering.availablePackages.associateBy { it.identifier }
        return offering.availablePackages.map { p ->
            PaywallPackage(
                id = p.identifier,
                productId = p.product.id,
                title = p.product.title,
                priceLabel = p.product.price.formatted,
                period = RevenueCatMapper.periodLabel(p.packageType.name),
            )
        }
    }

    override suspend fun purchase(packageId: String) {
        if (packages.isEmpty()) loadPackages()
        val pkg = packages[packageId] ?: error("That plan isn't available right now.")
        val act = activity.current() ?: error("Open the app to complete the purchase.")
        try {
            apply(Purchases.sharedInstance.awaitPurchase(PurchaseParams.Builder(act, pkg).build()).customerInfo)
        } catch (e: PurchasesTransactionException) {
            if (e.userCancelled) return
            throw e
        }
    }

    override suspend fun restore() {
        apply(Purchases.sharedInstance.awaitRestore())
    }

    /** Refreshes the entitlement from RevenueCat (e.g. on app foreground). */
    suspend fun refresh() {
        apply(Purchases.sharedInstance.awaitCustomerInfo())
    }
}

/**
 * Live mode without a RevenueCat key: purchases are unavailable (never a local Pro toggle). Entitlement still
 * follows the server-written `users/{uid}.subscription` map, so a user who bought Pro elsewhere (e.g. iOS) is Pro here.
 */
class UnconfiguredPurchaseRepository(
    profile: ProfileRepository? = null,
    scope: CoroutineScope? = null,
) : PurchaseRepository {
    private val _entitlement = MutableStateFlow(Entitlement.FREE)
    override val entitlement: StateFlow<Entitlement> = _entitlement.asStateFlow()

    init {
        if (profile != null && scope != null) {
            scope.launch {
                profile.observeProfile()
                    .catch { emit(null) }
                    .collect { p -> _entitlement.value = if (p?.serverIsPro == true) Entitlement(isPro = true) else Entitlement.FREE }
            }
        }
    }

    override suspend fun loadPackages(): List<PaywallPackage> = emptyList()

    override suspend fun purchase(packageId: String) {
        error("Subscriptions aren't configured in this build (missing revenuecat.apiKey).")
    }

    override suspend fun restore() = Unit
}
