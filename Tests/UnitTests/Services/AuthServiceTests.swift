import Testing
@testable import Garage

@MainActor
struct AuthServiceTests {
    @Test func localDemoAuthenticatesImmediatelyWithDemoUID() {
        let service = AuthService.localDemo
        #expect(service.isAuthenticated)
        #expect(service.uid == AppRuntime.demoUserId)
    }

    @Test func uiTestModeBlocksLiveSignIn() async {
        let service = AuthService(testUID: "test-user")
        do {
            try await service.signInWithApple(idToken: "token", nonce: "nonce")
            Issue.record("Expected UI-test authentication mode to reject live sign-in")
        } catch {
            #expect(error as? AppError == .auth("Authentication is disabled in UI tests"))
        }
    }

    @Test func signOutClearsInjectedStateAndNotifiesSink() throws {
        var values: [String?] = []
        let service = AuthService(testUID: "A", desiredUIDSink: { values.append($0) })
        try service.signOut()
        #expect(!service.isAuthenticated)
        #expect(service.uid == nil)
        #expect(values.count == 2)
        #expect(values[0] == "A")
        #expect(values[1] == nil)
    }

    @Test func accountSwitchDisablesAnalytics() {
        let analytics = AnalyticsSpy()
        let service = AuthService(testUID: "A", analytics: analytics)
        analytics.setEnabled(true)
        service.switchAuthenticatedUserForTesting(to: "B")
        #expect(service.uid == "B")
        #expect(analytics.enabledValues.last == false)
    }

    @Test func everyAppliedCallbackAdvancesAuthenticationRevision() {
        let service = AuthService(testUID: "A")
        #expect(service.authenticationRevision == 1)
        service.switchAuthenticatedUserForTesting(to: "A")
        #expect(service.authenticationRevision == 2)
        service.switchAuthenticatedUserForTesting(to: nil)
        #expect(service.authenticationRevision == 3)
    }
}
