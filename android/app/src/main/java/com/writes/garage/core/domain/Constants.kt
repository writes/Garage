package com.writes.garage.core.domain

/** Port of iOS `Constants` (values that must match the backend / store config). */
object Constants {
    const val MAX_FREE_VEHICLES = 1
    const val MAX_PRO_VEHICLES = 5
    const val DASHBOARD_RECENT_LIMIT = 10
    const val DEMO_USER_ID = "debug-user"

    // Store product ids; must match Play Console / RevenueCat exactly (see iOS Constants.swift).
    const val ANNUAL_PLAN_ID = "com.writes.harrysplayhouse.pro.yearly"
    const val MONTHLY_PLAN_ID = "com.writes.harrysplayhouse.pro.monthly"
    const val RECEIPT_CREDITS_PACK_ID = "com.writes.harrysplayhouse.credits.receipts10"

    const val MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024
    const val PRIVACY_POLICY_URL = "https://harrys-playhouse-prod.web.app/privacy"
    const val TERMS_OF_USE_URL = "https://harrys-playhouse-prod.web.app/terms"
}
