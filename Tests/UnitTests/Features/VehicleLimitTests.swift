import Foundation
import Testing
@testable import Garage

/// The free cap is 1 vehicle, so this rule decides what happens at the highest-intent conversion
/// moment in the product. Before the preflight existed, a free user filled the entire vehicle form
/// and waited for a Firestore round trip only to be handed a banner whose one button was
/// "Try Again" — for a condition retrying can never fix.
struct VehicleLimitTests {
    @Test func aFreeUserWithNoVehiclesCanAddOne() {
        #expect(VehicleLimit.canAdd(currentCount: 0, isPro: false))
    }

    @Test func aFreeUserAtTheCapCannotAddAnother() {
        #expect(!VehicleLimit.canAdd(currentCount: Constants.maxFreeVehicles, isPro: false))
    }

    @Test func proRaisesTheCap() {
        #expect(VehicleLimit.canAdd(currentCount: Constants.maxFreeVehicles, isPro: true))
        #expect(VehicleLimit.maximum(isPro: true) == Constants.maxProVehicles)
        #expect(VehicleLimit.maximum(isPro: false) == Constants.maxFreeVehicles)
    }

    @Test func aProUserAtTheProCapCannotAddAnother() {
        #expect(!VehicleLimit.canAdd(currentCount: Constants.maxProVehicles, isPro: true))
    }

    /// The offer must only appear when buying it actually changes the answer.
    @Test func upgradeIsOfferedOnlyToACappedFreeUser() {
        #expect(VehicleLimit.upgradeWouldHelp(currentCount: Constants.maxFreeVehicles, isPro: false))
        #expect(!VehicleLimit.upgradeWouldHelp(currentCount: 0, isPro: false))
    }

    /// Selling Pro to someone who already owns it, at a ceiling no purchase moves, is the failure
    /// this guards. It would be the same dead end as the original banner, with a payment sheet.
    @Test func aProUserAtTheirOwnCeilingIsNeverOfferedAnUpgrade() {
        #expect(!VehicleLimit.upgradeWouldHelp(currentCount: Constants.maxProVehicles, isPro: true))
    }

    /// A count above the cap is reachable — the cap can be lowered, or another device can write
    /// concurrently past the server check — and must not read as "room available".
    @Test func aCountAlreadyOverTheCapStillBlocks() {
        #expect(!VehicleLimit.canAdd(currentCount: Constants.maxProVehicles + 3, isPro: true))
        #expect(!VehicleLimit.canAdd(currentCount: Constants.maxFreeVehicles + 3, isPro: false))
    }
}
