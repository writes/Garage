import AuthenticationServices
import Observation

@MainActor
@Observable
final class AuthViewModel {
    private let authService: AuthService
    private var currentAppleNonce: String?

    private(set) var isLoading = false
    private(set) var error: AppError?

    init(authService: AuthService = .shared) {
        self.authService = authService
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.randomString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(nonce)
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

            try await authService.signInWithApple(
                idToken: idToken,
                nonce: nonce,
                fullName: credential.fullName
            )
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
            self.error = AppError(from: error)
        }
    }
}
