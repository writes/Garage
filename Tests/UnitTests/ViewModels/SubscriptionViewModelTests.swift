import Testing
@testable import Garage

private struct PurchasePresentationCase {
    let outcome: PurchaseOutcome
    let state: SubscriptionPresentationState
    let output: SubscriptionPresentationOutput
}

@MainActor
struct SubscriptionViewModelTests {
    @Test func initialNilPlansShowsSafeUnavailableCopy() {
        let model = SubscriptionViewModel(service: ScriptedSubscriptionFacade())
        #expect(model.presentationOutput == .notice(.plansUnavailable))
        #expect(!model.isBusy)
        #expect(model.diagnostics.actionCounter == 0)
    }

    @Test func refreshUsesOneTokenAcrossStatusAndOfferings() async {
        let facade = ScriptedSubscriptionFacade()
        facade.status = [.committed(SubscriptionFixtures.inactive)]
        facade.offerings = [.loaded(SubscriptionFixtures.plans)]
        facade.plans = SubscriptionFixtures.plans
        let model = SubscriptionViewModel(service: facade)
        await model.refreshTapped()
        #expect(facade.statusCalls == 1)
        #expect(facade.offeringsCalls == 1)
        #expect(model.state == .idle)
        #expect(model.diagnostics.actionCounter == 1)
        #expect(model.diagnostics.activeActionID == nil)
    }

    @Test func terminalStatusFailureSkipsOfferingsAndRetainsOnlySafeCopy() async {
        let facade = ScriptedSubscriptionFacade()
        facade.status = [.failed(.sdk(domain: "provider", code: 42, message: "secret details"))]
        let model = SubscriptionViewModel(service: facade)
        await model.refreshTapped()
        #expect(facade.offeringsCalls == 0)
        #expect(
            model.presentationOutput
                == .failure(.unknown("Your subscription status couldn't be refreshed. Try again."))
        )
        #expect(
            model.diagnostics.sdkFailureDiagnostic
                == .init(domain: "provider", code: 42, message: "secret details")
        )
    }

    @Test func purchaseOutcomeMappingIsExhaustiveForTrustStates() async {
        let cases: [PurchasePresentationCase] = [
            .init(outcome: .noEntitlement, state: .noEntitlement, output: .notice(.purchaseNoEntitlement)),
            .init(outcome: .cancelled, state: .cancelled, output: .notice(.cancelled)),
            .init(outcome: .busy, state: .idle, output: .notice(.busy)),
            .init(outcome: .notReady, state: .unavailable, output: .notice(.notReady)),
            .init(
                outcome: .selectionInvalidated,
                state: .selectionInvalidated,
                output: .notice(.selectionInvalidated)
            ),
            .init(
                outcome: .reconciliationRequired,
                state: .reconciliationRequired(.purchase),
                output: .reconciliation(.purchase)
            )
        ]
        for item in cases {
            let facade = ScriptedSubscriptionFacade()
            facade.selection = SubscriptionFixtures.selection
            facade.purchases = [item.outcome]
            let model = SubscriptionViewModel(service: facade)
            await model.choosePackageTapped(SubscriptionFixtures.package)
            #expect(model.state == item.state)
            #expect(model.presentationOutput == item.output)
        }
    }

    @Test func restoreOutcomeMappingCoversActiveNoActiveAndReconciliation() async {
        let facade = ScriptedSubscriptionFacade()
        facade.isPro = true
        facade.restores = [.activeEntitlement, .noActiveEntitlement, .reconciliationRequired]
        let model = SubscriptionViewModel(service: facade)
        await model.restoreTapped()
        #expect(model.presentationOutput == .notice(.active))
        facade.isPro = false
        await model.restoreTapped()
        #expect(model.presentationOutput == .notice(.restoreNoActive))
        await model.restoreTapped()
        #expect(model.presentationOutput == .reconciliation(.restore))
        #expect(model.diagnostics.actionCounter == 3)
    }

    @Test func nilSelectionDoesNotAdvanceCounterOrCallPurchase() async {
        let facade = ScriptedSubscriptionFacade()
        let model = SubscriptionViewModel(service: facade)
        await model.choosePackageTapped(SubscriptionFixtures.package)
        #expect(facade.selectionCalls == 1)
        #expect(facade.purchaseCalls == 0)
        #expect(model.diagnostics.actionCounter == 0)
        #expect(model.presentationOutput == .notice(.selectionInvalidated))
    }

    @Test func maxCounterFailsClosedWithZeroFacadeCallsForAllActions() async {
        let facade = ScriptedSubscriptionFacade()
        facade.selection = SubscriptionFixtures.selection
        let model = SubscriptionViewModel(service: facade)
        model.setActionCounterForTesting(.max)
        await model.refreshTapped()
        await model.restoreTapped()
        await model.choosePackageTapped(SubscriptionFixtures.package)
        #expect(facade.statusCalls == 0)
        #expect(facade.offeringsCalls == 0)
        #expect(facade.restoreCalls == 0)
        #expect(facade.selectionCalls == 0)
        #expect(facade.purchaseCalls == 0)
        #expect(model.presentationOutput == .notice(.notReady))
    }

    @Test func accountRevisionClearsStaleOutputButPreservesCurrentTruth() async {
        let facade = ScriptedSubscriptionFacade()
        facade.selection = SubscriptionFixtures.selection
        facade.purchases = [.cancelled]
        let model = SubscriptionViewModel(service: facade)
        await model.choosePackageTapped(SubscriptionFixtures.package)
        #expect(model.presentationOutput == .notice(.cancelled))
        facade.accountRevision = 1
        model.accountRevisionChanged(to: 1)
        #expect(model.state == .idle)
        #expect(model.presentationOutput == .notice(.plansUnavailable))
    }

    @Test func activeCopyIsSuppressedAsSoonAsComputedAuthorizationRevokes() async {
        let facade = ScriptedSubscriptionFacade()
        facade.isPro = true
        facade.selection = SubscriptionFixtures.selection
        facade.purchases = [.activePro]
        let model = SubscriptionViewModel(service: facade)
        await model.choosePackageTapped(SubscriptionFixtures.package)
        #expect(model.presentationOutput == .notice(.active))
        facade.isPro = false
        #expect(model.presentationOutput == .none)
    }

    @Test func accountRevisionDetachesOldPurchasePresentation() async {
        let facade = ScriptedSubscriptionFacade()
        facade.selection = SubscriptionFixtures.selection
        facade.purchases = [.activePro]
        facade.onPurchase = { facade.accountRevision = 1 }
        let model = SubscriptionViewModel(service: facade)

        await model.choosePackageTapped(SubscriptionFixtures.package)

        #expect(facade.purchaseCalls == 1)
        #expect(model.state == .idle)
        #expect(!model.isBusy)
        #expect(model.diagnostics.activeActionID == nil)
        #expect(model.presentationOutput == .notice(.plansUnavailable))
    }

    @Test func accountRevisionStopsOldRefreshBeforeOfferings() async {
        let facade = ScriptedSubscriptionFacade()
        facade.status = [.staleDiscarded]
        facade.onStatus = { facade.accountRevision = 1 }
        let model = SubscriptionViewModel(service: facade)

        await model.refreshTapped()

        #expect(facade.statusCalls == 1)
        #expect(facade.offeringsCalls == 0)
        #expect(model.state == .idle)
        #expect(!model.isBusy)
        #expect(model.presentationOutput == .notice(.plansUnavailable))
    }

    @Test func detachedCommerceRetainsReconciliationWarnings() async {
        let purchase = ScriptedSubscriptionFacade()
        purchase.selection = SubscriptionFixtures.selection
        purchase.purchases = [.reconciliationRequired]
        purchase.onPurchase = { purchase.accountRevision = 1 }
        let purchaseModel = SubscriptionViewModel(service: purchase)
        await purchaseModel.choosePackageTapped(SubscriptionFixtures.package)
        #expect(purchaseModel.presentationOutput == .reconciliation(.purchase))
        #expect(!purchaseModel.isBusy && !purchaseModel.isPro)
        let reopenedModel = SubscriptionViewModel(service: purchase)
        #expect(reopenedModel.presentationOutput == .reconciliation(.purchase))
        let selectionCalls = purchase.selectionCalls
        let purchaseCalls = purchase.purchaseCalls
        await reopenedModel.choosePackageTapped(SubscriptionFixtures.package)
        #expect(purchase.selectionCalls == selectionCalls)
        #expect(purchase.purchaseCalls == purchaseCalls)
        purchase.status = [.notReady]
        await purchaseModel.refreshTapped()
        #expect(purchaseModel.presentationOutput == .reconciliation(.purchase))
        purchase.restores = [.reconciliationRequired]
        purchase.onRestore = { purchase.accountRevision = 2 }
        await purchaseModel.restoreTapped()
        #expect(purchaseModel.presentationOutput == .reconciliation(.purchase))

        let restore = ScriptedSubscriptionFacade()
        restore.restores = [.reconciliationRequired]
        restore.onRestore = { restore.accountRevision = 1 }
        let restoreModel = SubscriptionViewModel(service: restore)
        await restoreModel.restoreTapped()
        #expect(restoreModel.presentationOutput == .reconciliation(.restore))
        #expect(!restoreModel.isBusy && !restoreModel.isPro)
    }

    @Test func disclosurePluralizesAndFailsClosedWithoutRenewalMetadata() {
        #expect(
            SubscriptionDisclosure.renewalTerms(
                localizedPrice: "$9.99",
                period: .init(value: 2, unit: .month)
            ) == "$9.99/2 months, auto-renews until cancelled."
        )
        #expect(
            SubscriptionDisclosure.renewalTerms(localizedPrice: "$49.99", period: nil)
                == "$49.99, renewal details unavailable. Purchase is disabled."
        )
    }
}
