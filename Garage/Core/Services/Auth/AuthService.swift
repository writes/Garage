import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import UIKit

@MainActor
@Observable
final class AuthService {
    private enum Mode {
        case live
        case localDemo
        case uiTest
    }

    static let shared = AuthService()
    static let localDemo = AuthService(mode: .localDemo)
    static let uiTest = AuthService(mode: .uiTest)

    private(set) var currentUser: FirebaseAuth.User?
    private(set) var isAuthenticated = false
    private var authListener: AuthStateDidChangeListenerHandle?
    private let mode: Mode

    private init(mode: Mode = .live) {
        self.mode = mode
        guard mode == .live else {
            isAuthenticated = mode == .localDemo
            return
        }

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }

    var uid: String? {
        if mode == .localDemo || AppRuntime.isLocalDemoMode {
            return AppRuntime.demoUserId
        }
        return currentUser?.uid
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

        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AppError.auth(
                "Google Sign-In is missing CLIENT_ID. Redownload GoogleService-Info.plist " +
                "for com.writes.harrysplayhouse.debug after enabling Google Auth in Firebase."
            )
        }

        guard let presentingViewController = Self.presentingViewController() else {
            throw AppError.auth("Google Sign-In could not find a view controller to present from.")
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let tokens = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GoogleSignInTokens, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: AppError.auth("Google Sign-In did not return a result."))
                    return
                }

                guard let idToken = result.user.idToken?.tokenString else {
                    continuation.resume(throwing: AppError.auth("Google Sign-In did not return an ID token."))
                    return
                }

                continuation.resume(returning: GoogleSignInTokens(
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                ))
            }
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: tokens.idToken,
            accessToken: tokens.accessToken
        )
        try await Auth.auth().signIn(with: credential)
    }

    func signOut() throws {
        guard !AppRuntime.isLocalDemoMode else { return }
        guard mode == .live else { return }
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
}

private extension AuthService {
    struct GoogleSignInTokens: Sendable {
        let idToken: String
        let accessToken: String
    }

    static func presentingViewController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        let window = windowScene?.windows.first { $0.isKeyWindow }
            ?? windowScene?.windows.first

        var viewController = window?.rootViewController
        while let presentedViewController = viewController?.presentedViewController {
            viewController = presentedViewController
        }
        return viewController
    }
}
