import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import Observation
import UIKit

@MainActor
@Observable
final class AuthService {
    private enum Mode { case live, localDemo, uiTest }

    static let shared = AuthService()
    static let localDemo = AuthService(mode: .localDemo)
    static let uiTest = AuthService(mode: .uiTest)

    private(set) var currentUser: FirebaseAuth.User?
    private(set) var isAuthenticated = false
    private var authListener: AuthStateDidChangeListenerHandle?
    private let mode: Mode
    private let analytics: any AnalyticsTracking
    private let desiredUIDSink: @MainActor @Sendable (String?) -> Void
    private var authenticationStateResolved = false
    private var authenticationStateWaiters: [CheckedContinuation<Void, Never>] = []
    private var testUID: String?
    private(set) var authenticationRevision = 0

    private init(
        mode: Mode = .live,
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.mode = mode
        self.analytics = analytics
        if mode == .live {
            desiredUIDSink = { uid in
                _ = PurchaseService.shared.setDesiredFirebaseUID(uid)
            }
        } else {
            desiredUIDSink = { _ in }
        }
        guard mode == .live else {
            isAuthenticated = mode == .localDemo
            authenticationStateResolved = true
            return
        }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.applyAuthenticationState(user) }
        }
    }

    #if DEBUG
    init(
        testUID: String?,
        desiredUIDSink: @escaping @MainActor @Sendable (String?) -> Void = { _ in },
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        mode = .uiTest
        self.testUID = testUID
        self.analytics = analytics
        self.desiredUIDSink = desiredUIDSink
        applyAuthenticationState(userID: testUID, firebaseUser: nil)
    }
    #endif

    var uid: String? {
        if mode == .localDemo || AppRuntime.isLocalDemoMode { return AppRuntime.demoUserId }
        return testUID ?? currentUser?.uid
    }

    func signInWithApple(
        idToken: String,
        nonce: String,
        fullName: PersonNameComponents? = nil
    ) async throws {
        guard mode == .live else { throw AppError.auth("Authentication is disabled in UI tests") }
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: fullName
        )
        try await Auth.auth().signIn(with: credential)
    }

    func signInWithGoogle() async throws {
        guard mode == .live else { throw AppError.auth("Authentication is disabled in UI tests") }
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AppError.auth(
                "Google Sign-In is missing CLIENT_ID. Redownload GoogleService-Info.plist " +
                    "for com.writes.harrysplayhouse.debug after enabling Google Auth in Firebase."
            )
        }
        guard let presenter = Self.presentingViewController() else {
            throw AppError.auth("Google Sign-In could not find a view controller to present from.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let tokens: GoogleSignInTokens = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error { continuation.resume(throwing: error); return }
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
        analytics.setEnabled(false)
        if mode == .localDemo {
            isAuthenticated = false
            authenticationRevision += 1
            return
        }
        guard !AppRuntime.isLocalDemoMode else { return }
        guard mode == .live else {
            testUID = nil
            applyAuthenticationState(userID: nil, firebaseUser: nil)
            return
        }
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
        applyAuthenticationState(userID: nil, firebaseUser: nil)
    }
}

private extension AuthService {
    func applyAuthenticationState(_ user: FirebaseAuth.User?) {
        applyAuthenticationState(userID: user?.uid, firebaseUser: user)
    }

    func applyAuthenticationState(userID: String?, firebaseUser: FirebaseAuth.User?) {
        analytics.setEnabled(false)
        currentUser = firebaseUser
        isAuthenticated = userID != nil
        authenticationRevision += 1
        desiredUIDSink(userID)
        resolveAuthenticationStateIfNeeded()
    }

    func resolveAuthenticationStateIfNeeded() {
        guard !authenticationStateResolved else { return }
        authenticationStateResolved = true
        let waiters = authenticationStateWaiters
        authenticationStateWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    struct GoogleSignInTokens: Sendable {
        let idToken: String
        let accessToken: String
    }

    static func presentingViewController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
        var viewController = window?.rootViewController
        while let presented = viewController?.presentedViewController { viewController = presented }
        return viewController
    }
}

#if DEBUG
extension AuthService {
    func switchAuthenticatedUserForTesting(to userID: String?) {
        testUID = userID
        applyAuthenticationState(userID: userID, firebaseUser: nil)
    }
}
#endif
