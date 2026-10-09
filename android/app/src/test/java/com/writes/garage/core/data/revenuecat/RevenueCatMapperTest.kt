package com.writes.garage.core.data.revenuecat

import com.writes.garage.core.domain.Constants
import com.writes.garage.core.model.Entitlement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class RevenueCatMapperTest {
    @Test
    fun entitlementIdMatchesIosAndServer() {
        assertEquals("pro", RevenueCatMapper.ENTITLEMENT_ID)
    }

    @Test
    fun inactiveIsFreeActiveIsProWithExpiry() {
        assertEquals(Entitlement.FREE, RevenueCatMapper.entitlement(false, "x", 1L, true))
        val e = RevenueCatMapper.entitlement(true, Constants.ANNUAL_PLAN_ID, 1_790_000_000_000L, willRenew = true)
        assertTrue(e.isPro)
        assertTrue(e.willRenew)
        assertEquals(Instant.ofEpochMilli(1_790_000_000_000L), e.expiresAt)
        assertFalse(RevenueCatMapper.entitlement(true, "p", null, false).willRenew)
    }

    @Test
    fun periodLabels() {
        assertEquals("year", RevenueCatMapper.periodLabel("ANNUAL"))
        assertEquals("month", RevenueCatMapper.periodLabel("MONTHLY"))
        assertEquals("", RevenueCatMapper.periodLabel("CUSTOM"))
    }

    @Test
    fun playProductIdsCarryABasePlanSuffix() {
        assertEquals(Constants.MONTHLY_PLAN_ID, RevenueCatMapper.subscriptionId(Constants.MONTHLY_PLAN_ID + ":monthly-base"))
        assertEquals(Constants.MONTHLY_PLAN_ID, RevenueCatMapper.subscriptionId(Constants.MONTHLY_PLAN_ID))
    }
}
