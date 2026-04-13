import Observation

@MainActor
@Observable
final class AuthViewModel {
    private let authService: AuthService

    private(set) var isLoading = false
    private(set) var error: AppError?

    init(authService: AuthService = .shared) {
        self.authService = authService
    }

    func signInWithApple(idToken: String, nonce: String) async {
        await perform {
            try await authService.signInWithApple(idToken: idToken, nonce: nonce)
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async {
        await perform {
            try await authService.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        }
    }

    func showSetupMessage() {
        error = .validation("Complete provider setup in Xcode, Firebase, and Apple Developer to finish sign-in wiring.")
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
