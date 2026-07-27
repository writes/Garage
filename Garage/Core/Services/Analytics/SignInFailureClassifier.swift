import AuthenticationServices
import Foundation

/// Maps a sign-in error onto the closed `SignInFailureReason` set.
///
/// This exists so `sign_in_failed` can carry a cause WITHOUT ever putting a provider's error
/// string into Analytics. Provider messages routinely embed the account email, a client ID, or a
/// token fragment; classifying to an enum at the boundary makes leaking one structurally
/// impossible rather than a matter of call-site discipline.
///
/// Deliberately pure and dependency-free (`Error` in, enum out) so the whole table is unit
/// testable without a live Firebase, Google, or Apple stack.
enum SignInFailureClassifier {
    static func reason(for error: Error) -> SignInFailureReason {
        // Cooperative cancellation — the Apple flow races sign-in against a timeout and cancels
        // the loser, so this must not be reported as a real failure.
        if error is CancellationError { return .cancelled }

        if let appError = error as? AppError, let mapped = reason(forAppError: appError) {
            return mapped
        }

        let nsError = error as NSError
        return appleReason(nsError)
            ?? urlReason(nsError)
            ?? googleReason(nsError)
            ?? .unknown
    }

    /// `ASAuthorizationError.canceled` is by far the most common outcome and is a user choice,
    /// not a defect.
    private static func appleReason(_ error: NSError) -> SignInFailureReason? {
        guard error.domain == ASAuthorizationError.errorDomain else { return nil }
        switch ASAuthorizationError.Code(rawValue: error.code) {
        case .canceled: return .cancelled
        case .invalidResponse, .notHandled: return .credential
        default: return .unknown
        }
    }

    private static func urlReason(_ error: NSError) -> SignInFailureReason? {
        guard error.domain == NSURLErrorDomain else { return nil }
        switch error.code {
        case NSURLErrorCancelled: return .cancelled
        case NSURLErrorTimedOut: return .timeout
        default: return .network
        }
    }

    /// Google Sign-In surfaces cancellation as code -5 in its own domain. Matched on the domain
    /// name rather than an imported constant to avoid coupling this file to the SDK.
    private static func googleReason(_ error: NSError) -> SignInFailureReason? {
        guard error.domain.contains("GIDSignIn") else { return nil }
        switch error.code {
        case -5: return .cancelled
        case -4: return .credential
        default: return .unknown
        }
    }

    /// `AppError.auth` carries human-facing copy, so classification here is necessarily
    /// message-shaped. The matched substrings are ones this app authors itself (see AuthService
    /// and AuthViewModel) — no provider text is inspected, and nothing matched here is emitted.
    private static func reason(forAppError error: AppError) -> SignInFailureReason? {
        if case .network = error { return .network }
        guard case .auth(let message) = error else { return nil }
        let lowered = message.lowercased()

        if lowered.contains("timed out") { return .timeout }
        if lowered.contains("client_id") || lowered.contains("disabled in ui tests") { return .configuration }
        if lowered.contains("view controller") { return .configuration }
        if lowered.contains("token") || lowered.contains("credential") { return .credential }
        if lowered.contains("did not return a result") { return .cancelled }
        return .unknown
    }
}
