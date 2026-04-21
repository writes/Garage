import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    private let authService: AuthService
    private let appleSignInTimeoutNanoseconds: UInt64
    private var currentAppleNonce: String?

    private(set) var isLoading = false
    private(set) var error: AppError?

    init(
        authService: AuthService = .shared,
        appleSignInTimeoutNanoseconds: UInt64 = Constants.appleSignInTimeoutNanoseconds
    ) {
        self.authService = authService
        self.appleSignInTimeoutNanoseconds = appleSignInTimeoutNanoseconds
    }

    static var simulatorHelpText: String? {
#if targetEnvironment(simulator)
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "this debug app ID"
        return
            "Simulator note: Sign in with Apple needs the simulator signed into an Apple ID, " +
            "and \(bundleIdentifier) must be enabled for Sign in with Apple in Apple Developer and Firebase."
#else
        return nil
#endif
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.randomString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(nonce)
        AppLogger.auth.info("Prepared Sign in with Apple request")
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        await perform {
            let authorization = try result.get()

            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AppError.auth("Apple did not return an Apple ID credential.")
            }

            guard let nonce = currentAppleNonce else {
                throw AppError.auth("Sign in with Apple did not start correctly. Try again.")
            }

            currentAppleNonce = nil

            guard let identityToken = credential.identityToken else {
                throw AppError.auth("Apple did not return an identity token.")
            }

            guard let idToken = String(data: identityToken, encoding: .utf8), !idToken.isEmpty else {
                throw AppError.auth("Apple returned an unreadable identity token.")
            }

            let signInTask = Task { @MainActor [authService] in
                try await authService.signInWithApple(
                    idToken: idToken,
                    nonce: nonce,
                    fullName: credential.fullName
                )
            }

            defer {
                signInTask.cancel()
            }

            let timeoutMessage = Self.appleSignInTimeoutMessage

            try await AsyncTimeout.run(
                nanoseconds: appleSignInTimeoutNanoseconds,
                timeoutError: AppError.auth(timeoutMessage)
            ) {
                try await signInTask.value
            }
        }
    }

    func signInWithGoogle() async {
        await perform {
            try await authService.signInWithGoogle()
        }
    }

    private func perform(_ task: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            error = nil
            try await task()
        } catch {
            AppLogger.auth.error("Authentication failed: \(error.localizedDescription)")
            self.error = AppError(from: error)
        }
    }

    private static var appleSignInTimeoutMessage: String {
#if targetEnvironment(simulator)
        return
            "Sign in with Apple timed out on the simulator. Sign into an Apple ID in the Simulator Settings app, " +
            "confirm the debug app ID is enabled for Sign in with Apple, or use a physical device."
#else
        return "Sign in with Apple timed out. Check your connection and try again."
#endif
    }
}
