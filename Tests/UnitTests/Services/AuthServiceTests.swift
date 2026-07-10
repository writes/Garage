import Testing
@testable import Garage

@MainActor
struct AuthServiceTests {
    @Test func localDemo_authenticatesImmediatelyWithDemoUID() {
        let service = AuthService.localDemo

        #expect(service.isAuthenticated)
        #expect(service.uid == AppRuntime.demoUserId)
    }

    @Test func uiTestMode_blocksLiveSignInAndSignOutClearsInjectedState() async {
        let service = AuthService(testUID: "test-user")

        do {
            try await service.signInWithApple(idToken: "token", nonce: "nonce")
            Issue.record("Expected UI-test authentication mode to reject live sign-in")
        } catch {
            #expect(error as? AppError == .auth("Authentication is disabled in UI tests"))
        }

        try? service.signOut()

        #expect(!service.isAuthenticated)
        #expect(service.uid == nil)
    }
}
