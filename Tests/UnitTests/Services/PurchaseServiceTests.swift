import Foundation
import Testing
@testable import Garage

@MainActor
struct PurchaseServiceTests {
    @Test func testInitializerIsSDKFreeAndComputedProMatchesSeed() {
        let free = PurchaseService(testIsPro: false)
        let pro = PurchaseService(testIsPro: true)
        #expect(!free.isPro); #expect(pro.isPro)
        #expect(free.accountRevision == 0)
        #expect(free.plans == nil)
    }

    @Test func stampReducerAppliesIgnoresAndRejectsExpectedCases() {
        let event = SubscriptionCommitEvent.revokedAll
        let accepted = StampedSubscriptionCommit(stamp: 2, event: event)
        #expect(SubscriptionStampReducer.disposition(incoming: accepted, lastAccepted: nil) == .apply)
        #expect(
            SubscriptionStampReducer.disposition(incoming: accepted, lastAccepted: accepted)
                == .ignoreExactDuplicate
        )
        let changed = StampedSubscriptionCommit(
            stamp: 2,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        )
        #expect(
            SubscriptionStampReducer.disposition(incoming: changed, lastAccepted: accepted)
                == .drop(.sameStampDifferentPayload(stamp: 2))
        )
    }

    @Test func accountRevisionReducerSaturatesAtMaximum() {
        #expect(SubscriptionAccountRevisionReducer.advance(from: 0) == .init(value: 1, overflowed: false))
        #expect(
            SubscriptionAccountRevisionReducer.advance(from: .max - 1)
                == .init(value: .max, overflowed: false)
        )
        #expect(
            SubscriptionAccountRevisionReducer.advance(from: .max)
                == .init(value: .max, overflowed: true)
        )
    }

    @Test func revocationClearsProofAndAdvancesRevision() {
        let client = SubscriptionMockClient()
        let service = makeTestService(client: client)
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        #expect(service.isPro)
        service.commit(.init(stamp: 2, event: .revokedAll))
        #expect(!service.isPro)
        #expect(service.accountRevision == 1)
        #expect(service.diagnostics.currentReadyLease == nil)
    }

    @Test func guardedLeaseMismatchClearsEverythingAndReports() {
        let client = SubscriptionMockClient()
        let reporter = SubscriptionReporterSpy()
        let service = makeTestService(client: client, reporter: reporter)
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
        ))
        service.commit(.init(
            stamp: 2,
            event: .statusCommitted(lease: SubscriptionFixtures.leaseB, snapshot: SubscriptionFixtures.active)
        ))
        #expect(!service.isPro)
        #expect(service.accountRevision == 1)
        #expect(reporter.violations == [.commitLeaseMismatch])
        #expect(service.diagnostics.lastAcceptedStamp == 2)
    }

    @Test func mismatchedErrorsClearBeforeAnyClockReadOrAnalytics() {
        let events: [SubscriptionCommitEvent] = [
            .currentError(
                lease: SubscriptionFixtures.leaseB,
                error: .sdk(domain: "test", code: 1, message: "offline")
            ),
            .offeringsUnavailable(lease: SubscriptionFixtures.leaseB, retiredEpoch: 3)
        ]
        for event in events {
            let clock = AdjustableEntitlementClock()
            let scheduler = ManualExpiryScheduler()
            let reporter = SubscriptionReporterSpy()
            let analytics = AnalyticsSpy()
            let service = makeTestService(
                client: SubscriptionMockClient(), clock: clock,
                reporter: reporter, analytics: analytics, scheduler: scheduler
            )
            service.commit(.init(
                stamp: 1,
                event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.active)
            ))
            service.commit(.init(stamp: 2, event: event))
            #expect(clock.reads == 0)
            #expect(scheduler.cancellations == 2)
            #expect(reporter.violations == [.commitLeaseMismatch])
            #expect(analytics.events.isEmpty)
            #expect(service.diagnostics.currentReadyLease == nil)
        }
    }

    @Test func sourcePinsCancelFirstRevisionAndReportOrdering() {
        let service = SubscriptionSourceProbe.read(
            "Garage/Core/Services/Subscription/PurchaseService.swift"
        )
        let state = SubscriptionSourceProbe.read(
            "Garage/Core/Services/Subscription/SubscriptionCommitRelay.swift"
        )
        #expect(SubscriptionSourceProbe.containsInOrder([
            "case .apply: state.lastAccepted = envelope",
            "let effects = applyStateEvent(envelope.event)",
            "effects.violations.forEach { relay.report($0) }",
            "perform(effects)"
        ], in: service))
        #expect(SubscriptionSourceProbe.containsInOrder([
            "expiryScheduler.cancelWake()",
            "return mutation()"
        ], in: service))
        #expect(SubscriptionSourceProbe.containsInOrder([
            "currentReadyLease = nil", "proof = nil", "plans = nil", "storedSelection = nil",
            "let step = SubscriptionAccountRevisionReducer.advance", "accountRevision = step.value",
            "[.commitLeaseMismatch]", ".accountRevisionOverflow"
        ], in: state))
    }

    @Test func canonicalSelectionUsesPublishedDTOAndCurrentLease() {
        let client = SubscriptionMockClient()
        let service = makeTestService(client: client)
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.inactive)
        ))
        service.commit(.init(
            stamp: 2,
            event: .offeringsLoaded(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.plans)
        ))
        let selection = service.makeSelection(for: SubscriptionFixtures.package)
        #expect(selection == SubscriptionFixtures.selection)
        var altered = SubscriptionFixtures.package
        altered = PackageDTO(
            handle: altered.handle, offeringID: altered.offeringID, packageID: altered.packageID,
            productID: altered.productID, analyticsProduct: .annual, title: altered.title,
            packageDescription: altered.packageDescription, localizedPrice: altered.localizedPrice,
            period: altered.period
        )
        #expect(service.makeSelection(for: altered) == nil)
    }

    @Test func activePurchaseCommitTracksOnceOnlyWhenProofIsValid() {
        let client = SubscriptionMockClient()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let service = makeTestService(client: client, analytics: analytics)
        service.commit(.init(
            stamp: 1,
            event: .identityApplied(lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.inactive)
        ))
        service.commit(.init(
            stamp: 2,
            event: .purchaseCompleted(
                lease: SubscriptionFixtures.leaseA,
                snapshot: SubscriptionFixtures.active,
                productID: .monthly
            )
        ))
        service.commit(.init(
            stamp: 2,
            event: .purchaseCompleted(
                lease: SubscriptionFixtures.leaseA,
                snapshot: SubscriptionFixtures.active,
                productID: .monthly
            )
        ))
        #expect(service.isPro)
        #expect(analytics.events == [.purchaseCompleted(productID: .monthly)])
    }

    @Test func compatibilityStatusWrapperRoutesThroughGateway() async {
        let client = SubscriptionMockClient()
        let service = makeTestService(client: client)
        let identity = service.setDesiredFirebaseUID("A")
        _ = await identity?.awaitValue()
        await service.checkSubscriptionStatus()
        #expect(client.loginUIDs == ["A"])
        #expect(client.statusCalls == 1)
    }

    @Test func disclosureUsesDTOPeriodAndUnknownFallback() {
        #expect(
            SubscriptionDisclosure.renewalTerms(
                localizedPrice: "$34.99",
                period: .init(value: 1, unit: .year)
            ) == "$34.99/year, auto-renews until cancelled."
        )
        #expect(
            SubscriptionDisclosure.renewalTerms(
                localizedPrice: "$1.99",
                period: .init(value: 2, unit: .unknown)
            ) == "$1.99, renewal details unavailable. Purchase is disabled."
        )
    }
}

@MainActor
struct SubscriptionRenewalSafetyTests {
    @Test func invalidRenewalMetadataCannotMintSelection() {
        let invalid = PackageDTO(
            handle: SubscriptionFixtures.package.handle,
            offeringID: SubscriptionFixtures.package.offeringID,
            packageID: SubscriptionFixtures.package.packageID,
            productID: SubscriptionFixtures.package.productID,
            analyticsProduct: SubscriptionFixtures.package.analyticsProduct,
            title: SubscriptionFixtures.package.title,
            packageDescription: SubscriptionFixtures.package.packageDescription,
            localizedPrice: SubscriptionFixtures.package.localizedPrice,
            period: nil
        )
        var state = PurchaseServiceState()
        state.currentReadyLease = SubscriptionFixtures.leaseA
        state.plans = OfferingsSnapshot(
            epoch: 1, offeringID: "default",
            packages: [invalid], omittedUnknownProductIDs: []
        )

        #expect(state.makeSelection(for: invalid, enabled: true) == nil)
        #expect(state.storedSelection == nil)
    }

    @Test func renewalValidationRejectsNilUnknownAndNonpositivePeriods() {
        #expect(SubscriptionFixtures.package.period?.isSupportedRenewal == true)
        #expect(SubscriptionPeriodDTO(value: 1, unit: .unknown).isSupportedRenewal == false)
        #expect(SubscriptionPeriodDTO(value: 0, unit: .month).isSupportedRenewal == false)
        #expect(SubscriptionPeriodDTO(value: -1, unit: .year).isSupportedRenewal == false)
        #expect(
            SubscriptionDisclosure.renewalTerms(localizedPrice: "$49.99", period: nil)
                == "$49.99, renewal details unavailable. Purchase is disabled."
        )
    }
}
