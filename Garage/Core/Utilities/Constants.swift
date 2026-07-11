import Foundation

enum Constants {
    static let maxFreeVehicles = 1
    static let pageSize = 20
    static let dashboardRecentLimit = 10
    static let annualPlanIdentifier = "garage_pro_annual"
    static let monthlyPlanIdentifier = "garage_pro_monthly"
    static let appleSignInTimeoutNanoseconds: UInt64 = 15_000_000_000
    // Operator action required before App Store submission: replace each
    // clearly-invalid placeholder with the published policy destination.
    static let privacyPolicyURLString = "https://OPERATOR-REPLACE-PRIVACY-POLICY.invalid"
    static let termsOfUseURLString = "https://OPERATOR-REPLACE-TERMS-OF-USE.invalid"
}

enum AppRuntime {
    static let localDemoLaunchArgument = "LOCAL_DEMO_MODE"
    static let uiTestLaunchArgument = "UI_TEST_MODE"
    static let uiTestProLaunchArgument = "UI_TEST_PRO"
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
    static func vehicleTireSets(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(tireSets)" }
    static func vehicleReminders(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(reminders)" }
    static func vehicleGallery(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(gallery)" }
    static func vehicleParts(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(partsInventory)" }
    static func vehicleDetailing(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(detailingRecords)" }
    static func vehicleWarranties(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(warranties)" }
    static func vehicleRecalls(vehicleId: String) -> String { "\(vehicles)/\(vehicleId)/\(recalls)" }
}

enum StoragePaths {
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
