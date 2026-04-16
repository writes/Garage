import Foundation
import FirebaseAuth
import Observation

@MainActor
@Observable
final class AuthService {
    private enum Mode {
        case live
        case uiTest
    }

    static let shared = AuthService()
    static let uiTest = AuthService(mode: .uiTest)

    private(set) var currentUser: FirebaseAuth.User?
    private(set) var isAuthenticated = false
    private var authListener: AuthStateDidChangeListenerHandle?
    private let mode: Mode

    private init(mode: Mode = .live) {
        self.mode = mode
        guard mode == .live else { return }

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }

    var uid: String? {
        currentUser?.uid
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents? = nil) async throws {
        guard mode == .live else {
            throw AppError.auth("Authentication is disabled in UI tests")
        }

        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: fullName)
        try await Auth.auth().signIn(with: credential)
    }

    func signInWithGoogle() async throws {
        guard mode == .live else {
            throw AppError.auth("Authentication is disabled in UI tests")
        }

        let provider = OAuthProvider.provider(providerID: .google, auth: Auth.auth())
        try await Auth.auth().signIn(with: provider, uiDelegate: nil)
    }

    func signOut() throws {
        guard mode == .live else { return }
        try Auth.auth().signOut()
    }
}
