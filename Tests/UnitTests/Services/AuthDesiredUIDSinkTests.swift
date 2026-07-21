import Testing
@testable import Garage

private struct AuthSinkObservation {
    let uid: String?
    let isAuthenticated: Bool
    let revision: Int
}

@MainActor
struct AuthDesiredUIDSinkTests {
    @Test func initialStateIsPublishedBeforeSynchronousSinkRuns() {
        var observed: [AuthSinkObservation] = []
        var service: AuthService?
        service = AuthService(testUID: nil, desiredUIDSink: { uid in
            observed.append(AuthSinkObservation(
                uid: uid,
                isAuthenticated: service?.isAuthenticated ?? false,
                revision: service?.authenticationRevision ?? 1
            ))
        })
        #expect(observed.count == 1)
        #expect(observed[0].uid == nil)
        #expect(observed[0].isAuthenticated == false)
        #expect(observed[0].revision == 1)
    }

    @Test func switchPublishesStateBeforeSinkAndReturnsSynchronously() {
        var states: [AuthSinkObservation] = []
        var service: AuthService?
        service = AuthService(testUID: nil, desiredUIDSink: { uid in
            guard let service else { return }
            states.append(AuthSinkObservation(
                uid: uid,
                isAuthenticated: service.isAuthenticated,
                revision: service.authenticationRevision
            ))
        })
        service?.switchAuthenticatedUserForTesting(to: "B")
        #expect(states.count == 1)
        #expect(states[0].uid == "B")
        #expect(states[0].isAuthenticated)
        #expect(states[0].revision == 2)
    }

    @Test func duplicateCallbackIsForwardedWithoutAuthLayerDedupe() {
        var values: [String?] = []
        let service = AuthService(testUID: "A", desiredUIDSink: { values.append($0) })
        service.switchAuthenticatedUserForTesting(to: "A")
        #expect(values.count == 2)
        #expect(values.allSatisfy { $0 == "A" })
    }

    @Test func injectedInstancesStayIsolatedFromEachOther() {
        var first: [String?] = []
        var second: [String?] = []
        let firstService = AuthService(testUID: "A", desiredUIDSink: { first.append($0) })
        let secondService = AuthService(testUID: "B", desiredUIDSink: { second.append($0) })
        firstService.switchAuthenticatedUserForTesting(to: "C")
        #expect(first.count == 2)
        #expect(first.last == "C")
        #expect(second == ["B"])
        _ = secondService
    }

    @Test func synchronousSinkRegistersThenExplicitlyRecoversFailedIdentity() async {
        let client = SubscriptionMockClient()
        let error = SubscriptionError.sdk(domain: "auth-sink", code: 4, message: "offline")
        var attempts = 0
        client.loginHandler = { uid in
            attempts += 1
            if attempts == 1 { return client.observed(.failure(error), uid: uid) }
            return client.observed(.success(SubscriptionFixtures.inactive), uid: uid)
        }
        let relay = SubscriptionCommitRelay(reporter: SubscriptionReporterSpy())
        relay.bind(SubscriptionCommitSinkSpy())
        let gateway = SubscriptionGateway(client: client, relay: relay)
        let service = AuthService(testUID: "A", desiredUIDSink: { uid in
            _ = gateway.setDesiredFirebaseUID(uid)
        })
        #expect(gateway.diagnostics.desiredFirebaseUID == "A")
        #expect(await gateway.requestIdentityRetry().awaitValue() == .failed(error))
        service.switchAuthenticatedUserForTesting(to: "A")
        #expect(client.loginUIDs == ["A"])
        #expect(await gateway.requestIdentityRetry().awaitValue() == .applied(SubscriptionFixtures.leaseA))
        #expect(client.loginUIDs == ["A", "A"])
    }

    @Test func compatibilityInitializersRemainAvailable() {
        let analytics = AnalyticsSpy()
        let plain = AuthService(testUID: nil)
        let withAnalytics = AuthService(testUID: "A", analytics: analytics)
        #expect(plain.uid == nil)
        #expect(withAnalytics.uid == "A")
    }
}
