import Foundation

/// The free-tier vehicle cap, as a client-side *preflight*.
///
/// Enforcement stays where it was — `VehicleService.validateVehicleLimit` throws
/// `AppError.vehicleLimitReached` server-side, and that remains the only thing standing between a
/// modified client and an over-cap write. What was missing was anything in front of it: a free
/// user tapped "Add Vehicle", filled in nickname, make, model, year, VIN and odometer, waited for
/// a Firestore round trip, and was handed a bare error banner whose only button said "Try Again"
/// — for a condition retrying can never fix. Every other Pro boundary in the app (Stats, Export,
/// theme picker, attachments) routes to `ProGateView` with a real offer; this one, the highest-
/// intent conversion moment in the product, offered nothing.
///
/// Kept as a pure static so the rule is testable without an AppState, a purchase service, or a
/// main actor, and lives in its own file because AppState.swift sits exactly on the 250-line cap.
enum VehicleLimit {
    static func maximum(isPro: Bool) -> Int {
        isPro ? Constants.maxProVehicles : Constants.maxFreeVehicles
    }

    static func canAdd(currentCount: Int, isPro: Bool) -> Bool {
        currentCount < maximum(isPro: isPro)
    }

    /// Pro users can hit their own ceiling too, and no purchase resolves that — so the paywall
    /// must not be offered to someone who has already bought everything there is to buy.
    static func upgradeWouldHelp(currentCount: Int, isPro: Bool) -> Bool {
        !isPro && !canAdd(currentCount: currentCount, isPro: false)
    }
}

extension AppState {
    var canAddVehicle: Bool {
        VehicleLimit.canAdd(currentCount: vehicles.count, isPro: isPro)
    }

    var vehicleLimitUpgradeWouldHelp: Bool {
        VehicleLimit.upgradeWouldHelp(currentCount: vehicles.count, isPro: isPro)
    }
}
