import Foundation

enum Constants {
    static let maxFreeVehicles = 1
    static let maxProVehicles = 5
    static let pageSize = 20
    /// One Log page. The tab used to fetch `maxLogEntries` (500) documents on EVERY revision bump
    /// and again per Load More, so a returning owner paid a 500-document read to look at the dozen
    /// rows that fit on screen. Load More pages older history in progressively — the cursor
    /// semantics that make that safe live in EntryService.fetchEntries.
    static let logPageSize = 50
    /// Not a fetch bound any more — only the Log footer's "showing the most recent N" caption.
    static let maxLogEntries = 500
    static let dashboardRecentLimit = 10
    /// STORE product identifiers, and they must match App Store Connect **exactly**.
    ///
    /// The offerings pipeline filters every package through
    /// `AnalyticsProductID(storeProductIdentifier:)`, which returns nil for anything it does not
    /// recognise; unrecognised products are dropped into `omittedUnknownProductIDs` and never
    /// rendered. So a mismatch here does not fail loudly — **it produces an empty paywall**, with
    /// no error, no crash, and nothing purchasable.
    ///
    /// These previously read `garage_pro_annual` / `garage_pro_monthly`, which exist nowhere in
    /// App Store Connect (RevenueCat listed both as "Not found"). Note the store uses `yearly`,
    /// not `annual`.
    ///
    /// NOT the same thing as `AnalyticsProductID`'s raw values, which are stable analytics labels
    /// and deliberately unchanged — renaming those would silently break every saved Firebase
    /// funnel keyed on `product_id`.
    static let annualPlanIdentifier = "com.writes.harrysplayhouse.pro.yearly"
    static let monthlyPlanIdentifier = "com.writes.harrysplayhouse.pro.monthly"
    /// The receipt-credits CONSUMABLE (+10 saves, $0.99). Purchased via the direct-product path
    /// (`ReceiptCreditsPurchaser`), NEVER through offerings — the subscriptions pipeline
    /// structurally drops period-less products. Must match ASC and the server's
    /// CREDITS_PRODUCT_IDS exactly; a mismatch hides the offer silently (availability probe
    /// fails), it never crashes.
    static let receiptCreditsPackIdentifier = "com.writes.harrysplayhouse.credits.receipts10"
    static let appleSignInTimeoutNanoseconds: UInt64 = 15_000_000_000
    /// Headroom under firebase.storage.rules' 25MB owner-write ceiling for entry attachments —
    /// checked client-side (AttachmentPicker) before a PDF is ever read into memory, so an
    /// oversized pick fails fast with a clear error instead of a late Storage-rules rejection.
    static let maxAttachmentBytes = 20 * 1024 * 1024
    /// Ceiling for EntryAttachmentService.downloadData(for:)'s StorageReference.data(maxSize:) —
    /// matches firebase.storage.rules' <25MB write ceiling exactly (not maxAttachmentBytes' 20MB
    /// upload headroom) so a legitimately-stored attachment near that ceiling is never truncated
    /// on download.
    static let maxAttachmentDownloadBytes = 25 * 1024 * 1024
    // Published 2026-07-24 to Firebase Hosting on harrys-playhouse-prod, rendered from
    // docs/legal/*_DRAFT.md by scripts/release/legal_site.py. Re-run `legal_site.py render`
    // and redeploy hosting after editing either draft — the generator refuses to publish a
    // document that still contains an unfilled placeholder.
    static let privacyPolicyURLString = "https://harrys-playhouse-prod.web.app/privacy"
    static let termsOfUseURLString = "https://harrys-playhouse-prod.web.app/terms"
}

enum AppRuntime {
    static let localDemoLaunchArgument = "LOCAL_DEMO_MODE"
    static let uiTestLaunchArgument = "UI_TEST_MODE"
    static let uiTestProLaunchArgument = "UI_TEST_PRO"
    /// Demo/UI-test profiles seed AI consent as already granted so the existing journeys never
    /// meet the first-use gate; this argument seeds the opposite so one journey can drive it.
    static let uiTestAIConsentUnsetLaunchArgument = "UI_TEST_AI_CONSENT_UNSET"
    static let demoUserId = "debug-user"

    static var isLocalDemoMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(localDemoLaunchArgument)
#else
        false
#endif
    }

    static var isUITestPro: Bool {
#if DEBUG
        isLocalDemoMode && ProcessInfo.processInfo.arguments.contains(uiTestProLaunchArgument)
#else
        false
#endif
    }

    static var isUITestAIConsentUnset: Bool {
#if DEBUG
        isLocalDemoMode && ProcessInfo.processInfo.arguments.contains(uiTestAIConsentUnsetLaunchArgument)
#else
        false
#endif
    }

    static var isUITestMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(uiTestLaunchArgument)
#else
        false
#endif
    }
}

enum FirestorePaths {
    static let users = "users"
    static let vehicles = "vehicles"
    static let entries = "entries"
    static let attachments = "attachments"
    static let wearSnapshots = "wear_snapshots"
    static let tireSets = "tire_sets"
    static let reminders = "reminders"
    static let gallery = "gallery"
    static let partsInventory = "parts_inventory"
    static let detailingRecords = "detailing_records"
    static let warranties = "warranties"
    static let recalls = "recalls"

    static func vehicleEntries(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(entries)" }
    static func vehicleWear(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(wearSnapshots)" }
    static func vehicleReminders(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(reminders)" }
    static func vehicleGallery(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(gallery)" }
    static func vehicleParts(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(partsInventory)" }
    static func vehicleDetailing(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(detailingRecords)" }
    static func vehicleWarranties(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(warranties)" }
    static func vehicleRecalls(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(recalls)" }
}

enum StoragePaths {
    /// Real attachments pipeline (external audit: "attachments retain filenames rather than
    /// evidence"). Under users/{uid}/ so the existing owner-only/<=25MB/image-or-pdf Storage
    /// rules and the deleteAccount cascade already cover it without a rules change.
    static func entryAttachment(userId: String, vehicleId: String, entryId: String, filename: String) -> String {
        "users/\(userId)/entry-attachments/\(vehicleId)/\(entryId)/\(filename)"
    }

    static func receipt(userId: String, vehicleId: String, entryId: String, filename: String) -> String {
        "users/\(userId)/vehicles/\(vehicleId)/receipts/\(entryId)/\(filename)"
    }

    static func photo(userId: String, vehicleId: String, entryId: String, filename: String) -> String {
        "users/\(userId)/vehicles/\(vehicleId)/photos/\(entryId)/\(filename)"
    }

    static func gallery(userId: String, vehicleId: String, filename: String) -> String {
        "users/\(userId)/vehicles/\(vehicleId)/gallery/\(filename)"
    }

    static func report(userId: String, vehicleId: String, filename: String) -> String {
        "users/\(userId)/vehicles/\(vehicleId)/reports/\(filename)"
    }
}
