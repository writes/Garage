import AuthenticationServices
import Foundation
import Testing
@testable import Garage

struct AppErrorTests {
    @Test func networkNSError_mapsToNetwork() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "Offline"]
        )

        #expect(AppError(from: error) == .network("Offline"))
    }

    @Test func appleAuthorizationUnknown_mapsToActionableAuthError() {
        let error = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.Code.unknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed."]
        )

#if targetEnvironment(simulator)
        let expectedMessage =
            "Sign in with Apple couldn't start on the simulator. Verify the debug app ID is enabled " +
            "for Sign in with Apple, the capability is present in this build, and the simulator is signed into an Apple ID."
#else
        let expectedMessage =
            "Sign in with Apple couldn't start for this build. " +
            "Rebuild and verify the Sign in with Apple capability is enabled."
#endif

        #expect(
            AppError(from: error) == .auth(expectedMessage)
        )
    }
}
