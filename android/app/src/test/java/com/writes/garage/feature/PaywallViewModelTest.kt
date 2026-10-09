package com.writes.garage.feature

import com.writes.garage.core.model.Entitlement
import com.writes.garage.feature.settings.PaywallViewModel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Money path: the paywall must never claim Pro (or a restore) that did not happen. */
class PaywallViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun userCancelReturnsNormallyButIsNotAClaimedPurchase() = runTest {
        val repo = FakePurchases().apply { purchaseGrantsPro = false } // RevenueCat returns normally on cancel
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.purchase("annual")
        val s = vm.state.value
        assertEquals(1, repo.purchaseCalls)
        assertFalse(s.isPro)
        assertNull("no success claim after a cancel", s.message)
        assertNull(s.error)
        assertFalse(s.busy)
    }

    @Test
    fun successfulPurchaseClaimsProOnlyBecauseEntitlementFlipped() = runTest {
        val repo = FakePurchases()
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.purchase("annual")
        assertTrue(vm.state.value.isPro)
        assertEquals("Thanks! Garage Pro is active.", vm.state.value.message)
        assertFalse(vm.state.value.busy)
    }

    @Test
    fun failedPurchaseSetsErrorAndClearsBusy() = runTest {
        val repo = FakePurchases().apply { purchaseFailure = IllegalStateException("Billing unavailable") }
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.purchase("annual")
        val s = vm.state.value
        assertEquals("Billing unavailable", s.error)
        assertNull(s.message)
        assertFalse(s.busy)
        assertFalse(s.isPro)
    }

    @Test
    fun failureWithoutMessageFallsBackToGenericCopy() = runTest {
        val repo = FakePurchases().apply { purchaseFailure = RuntimeException() }
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.purchase("annual")
        assertEquals("Purchase failed.", vm.state.value.error)
    }

    @Test
    fun restoreThatFindsNothingDoesNotSayRestored() = runTest {
        val repo = FakePurchases().apply { restoreGrantsPro = false }
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.restore()
        val s = vm.state.value
        assertEquals(1, repo.restoreCalls)
        assertFalse(s.isPro)
        assertNotNull(s.message)
        assertFalse("must not claim a restore", s.message!!.contains("restored", ignoreCase = true))
        assertFalse(s.busy)
    }

    @Test
    fun restoreThatFindsASubscriptionSaysRestored() = runTest {
        val repo = FakePurchases().apply { restoreGrantsPro = true }
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.restore()
        assertTrue(vm.state.value.isPro)
        assertEquals("Purchases restored.", vm.state.value.message)
    }

    @Test
    fun restoreFailureSetsError() = runTest {
        val repo = FakePurchases().apply { restoreFailure = RuntimeException("offline") }
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.restore()
        assertEquals("offline", vm.state.value.error)
        assertNull(vm.state.value.message)
        assertFalse(vm.state.value.busy)
    }

    @Test
    fun secondPurchaseWhileBusyIsIgnored() = runTest {
        val gate = CompletableDeferred<Unit>()
        val repo = FakePurchases().apply { purchaseGate = gate }
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.purchase("annual")
        assertTrue(vm.state.value.busy)
        vm.purchase("annual")
        vm.restore()
        assertEquals("a double tap must not start a second purchase", 1, repo.purchaseCalls)
        assertEquals("restore is also blocked while a purchase is in flight", 0, repo.restoreCalls)
        gate.complete(Unit)
        assertFalse(vm.state.value.busy)
        assertTrue(vm.state.value.isPro)
    }

    @Test
    fun packageLoadFailureIsSurfacedAndLoadedStillTrue() = runTest {
        val repo = FakePurchases().apply { packagesFailure = RuntimeException("no offerings") }
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        assertTrue(vm.state.value.loaded)
        assertEquals("no offerings", vm.state.value.error)
        assertTrue(vm.state.value.packages.isEmpty())
    }

    @Test
    fun alreadyProUserRestoreIsStillTruthful() = runTest {
        val repo = FakePurchases(Entitlement(isPro = true))
        val vm = PaywallViewModel(repo)
        keepHot(vm.state)
        vm.restore()
        assertEquals("Purchases restored.", vm.state.value.message)
    }
}
