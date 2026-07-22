import Testing
@testable import Garage

@MainActor
struct SubscriptionOfferingsTests {
    @Test func loadedAndUnavailableOutcomesCarryTheExpectedCommitEvidence() async {
        let client = SubscriptionMockClient()
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        client.offeringsHandler = {
            client.observed(.success(.loaded(SubscriptionFixtures.plans)))
        }
        #expect(await gateway.registerOfferings().awaitValue() == .loaded(SubscriptionFixtures.plans))
        #expect(gateway.diagnostics.currentOfferingsEpoch == 1)
        client.offeringsHandler = { client.observed(.success(.unavailable(epoch: 2))) }
        #expect(await gateway.registerOfferings().awaitValue() == .unavailable)
        #expect(gateway.diagnostics.currentOfferingsEpoch == nil)
        #expect(
            sink.envelopes.last?.event
                == .offeringsUnavailable(lease: SubscriptionFixtures.leaseA, retiredEpoch: 2)
        )
    }

    @Test func currentSDKErrorRetiresEpochAndEmitsCurrentError() async {
        let client = SubscriptionMockClient()
        let error = SubscriptionError.sdk(domain: "network", code: -1, message: "offline")
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        client.offeringsHandler = {
            client.observed(.success(.loaded(SubscriptionFixtures.plans)))
        }
        _ = await gateway.registerOfferings().awaitValue()
        client.offeringsHandler = { client.observed(.failure(error)) }
        let invalidations = client.invalidationCount
        #expect(await gateway.registerOfferings().awaitValue() == .failed(error))
        #expect(client.invalidationCount == invalidations + 1)
        #expect(gateway.diagnostics.currentOfferingsEpoch == nil)
        #expect(sink.envelopes.last?.event == .currentError(lease: SubscriptionFixtures.leaseA, error: error))
    }

    @Test func staleHeldOfferingCannotCommitOrInvalidateAfterSwitch() async {
        let client = SubscriptionMockClient()
        let held = HeldValue<RevenueCatObserved<ClientOfferingsPayload>>()
        client.offeringsHandler = { await held.load() }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        let offerings = gateway.registerOfferings()
        let id = await held.waitForStart()
        _ = gateway.setDesiredFirebaseUID("B")
        let invalidations = client.invalidationCount
        held.resolve(id, with: client.observed(
            .success(.loaded(SubscriptionFixtures.plans)), uid: "A"
        ))
        #expect(await offerings.awaitValue() == .staleDiscarded)
        #expect(client.invalidationCount == invalidations)
        #expect(!sink.envelopes.contains {
            $0.event == .offeringsLoaded(
                lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.plans
            )
        })
    }

    @Test func currentObservedUIDMismatchRevokesAndRetiresEpoch() async {
        let client = SubscriptionMockClient()
        client.offeringsHandler = {
            client.observed(.success(.loaded(SubscriptionFixtures.plans)), uid: "B")
        }
        let sink = SubscriptionCommitSinkSpy()
        let gateway = makeGateway(client, sink: sink)
        _ = await gateway.setDesiredFirebaseUID("A")?.awaitValue()
        #expect(await gateway.registerOfferings().awaitValue() == .failed(.identityMismatch))
        #expect(gateway.diagnostics.currentOfferingsEpoch == nil)
        #expect(gateway.diagnostics.readyLease == nil)
        #expect(sink.envelopes.last?.event == .revokedAll)
        #expect(!sink.envelopes.contains {
            $0.event == .offeringsLoaded(
                lease: SubscriptionFixtures.leaseA, snapshot: SubscriptionFixtures.plans
            )
        })
    }

    @Test func liveAdapterMapsKnownProductsAndDiagnosesUnknownProducts() async {
        let uid = SubscriptionStringBox("A")
        let adapter = LiveRevenueCatClient(
            observedUserID: { uid.value },
            offeringsExecutor: {
                RawOfferingFacts(
                    offeringID: "default",
                    packages: renewalAdmissionFacts()
                )
            }
        )
        let observed = await adapter.offerings()
        guard case .success(.loaded(let snapshot)) = observed.result else {
            Issue.record("Expected loaded mapped offering")
            return
        }
        #expect(snapshot.packages.count == 1)
        #expect(snapshot.packages[0].analyticsProduct == .monthly)
        #expect(snapshot.omittedUnknownProductIDs == [
            "unknown.product",
            Constants.annualPlanIdentifier,
            Constants.annualPlanIdentifier,
            Constants.annualPlanIdentifier
        ])
        uid.value = "B"
        #expect(adapter.appUserID == "B")
    }

    @Test func midflightInvalidationCannotRepopulateAdapterCache() async {
        let held = HeldValue<RawOfferingFacts?>()
        let adapter = LiveRevenueCatClient(
            observedUserID: { "A" },
            offeringsExecutor: { await held.load() }
        )
        let task = Task { await adapter.offerings() }
        let id = await held.waitForStart()
        adapter.invalidatePackageCache()
        held.resolve(id, with: RawOfferingFacts(
            offeringID: "default",
            packages: [RawPackageFacts(
                packageID: "monthly", productID: Constants.monthlyPlanIdentifier,
                title: "Monthly", packageDescription: "Known", localizedPrice: "$4.99",
                period: .init(value: 1, unit: .month)
            )]
        ))
        let observed = await task.value
        #expect(observed.result == .success(.cacheInvalidated))
    }

    @Test func adapterFinalFenceRejectsAlteredProductBeforeExecutor() async {
        let purchaseCalls = SubscriptionCounter()
        let adapter = LiveRevenueCatClient(
            observedUserID: { "A" },
            offeringsExecutor: {
                RawOfferingFacts(
                    offeringID: "default",
                    packages: [RawPackageFacts(
                        packageID: "monthly", productID: Constants.monthlyPlanIdentifier,
                        title: "Monthly", packageDescription: "Known", localizedPrice: "$4.99",
                        period: .init(value: 1, unit: .month)
                    )]
                )
            },
            purchaseExecutor: { _, _, _, _, _ in
                purchaseCalls.increment()
                return RawPurchaseResult(userCancelled: false, snapshot: SubscriptionFixtures.active)
            }
        )
        let offering = await adapter.offerings()
        guard case .success(.loaded(let snapshot)) = offering.result,
              let package = snapshot.packages.first else { return }
        let result = await adapter.purchase(
            handle: package.handle, offeringID: package.offeringID,
            packageID: package.packageID, productID: "altered",
            analyticsProduct: package.analyticsProduct
        )
        #expect(result.result == .success(.selectionInvalidated))
        #expect(purchaseCalls.value == 0)
    }

    private func makeGateway(
        _ client: SubscriptionMockClient,
        sink: SubscriptionCommitSinkSpy
    ) -> SubscriptionGateway {
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(sink)
        return SubscriptionGateway(client: client, relay: relay)
    }
}

private func renewalAdmissionFacts() -> [RawPackageFacts] {
    [
        RawPackageFacts(
            packageID: "monthly", productID: Constants.monthlyPlanIdentifier,
            title: "Monthly", packageDescription: "Known", localizedPrice: "$4.99",
            period: .init(value: 1, unit: .month)
        ),
        RawPackageFacts(
            packageID: "mystery", productID: "unknown.product", title: "Mystery",
            packageDescription: "Unknown", localizedPrice: "$9.99", period: nil
        ),
        RawPackageFacts(
            packageID: "annual-nil", productID: Constants.annualPlanIdentifier,
            title: "Annual", packageDescription: "Missing period",
            localizedPrice: "$34.99", period: nil
        ),
        RawPackageFacts(
            packageID: "annual-unknown", productID: Constants.annualPlanIdentifier,
            title: "Annual", packageDescription: "Unknown period",
            localizedPrice: "$34.99", period: .init(value: 1, unit: .unknown)
        ),
        RawPackageFacts(
            packageID: "annual-zero", productID: Constants.annualPlanIdentifier,
            title: "Annual", packageDescription: "Invalid period",
            localizedPrice: "$34.99", period: .init(value: 0, unit: .year)
        )
    ]
}
