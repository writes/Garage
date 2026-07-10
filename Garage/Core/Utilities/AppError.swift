import AuthenticationServices
import Foundation

enum AppError: LocalizedError, Equatable, Sendable {
    case network(String)
    case auth(String)
    case database(String)
    case storage(String)
    case validation(String)
    case subscriptionRequired(String)
    case vehicleLimitReached
    case syncConflict(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "Network error: \(message)"
        case .auth(let message):
            return "Auth error: \(message)"
        case .database(let message):
            return "Database error: \(message)"
        case .storage(let message):
            return "Storage error: \(message)"
        case .validation(let message):
            return message
        case .subscriptionRequired(let feature):
            return "Pro required for \(feature)"
        case .vehicleLimitReached:
            return "Free accounts are limited to 1 vehicle. Upgrade to Pro for unlimited."
        case .syncConflict(let message):
            return "Sync conflict: \(message)"
        case .unknown(let message):
            return message
        }
    }

    init(from error: Error) {
        let nsError = error as NSError
        switch nsError.domain {
        case "FIRAuthErrorDomain":
            self = .auth(nsError.localizedDescription)
        case ASAuthorizationError.errorDomain:
            self = .auth(Self.appleAuthorizationMessage(for: nsError))
        case "FIRFirestoreErrorDomain":
            self = .database(nsError.localizedDescription)
        case "FIRStorageErrorDomain":
            self = .storage(nsError.localizedDescription)
        case NSURLErrorDomain:
            self = .network(nsError.localizedDescription)
        default:
            self = .unknown(nsError.localizedDescription)
        }
    }

    private static func appleAuthorizationMessage(for error: NSError) -> String {
        if error.code == ASAuthorizationError.Code.canceled.rawValue {
            return "Sign in with Apple was canceled."
        }

        if error.code == ASAuthorizationError.Code.unknown.rawValue {
#if targetEnvironment(simulator)
            return
                "Sign in with Apple couldn't start on the simulator. Verify the debug app ID is enabled " +
                "for Sign in with Apple, the capability is present in this build, and the simulator is signed into " +
                "an Apple ID."
#else
            return
                "Sign in with Apple couldn't start for this build. " +
                "Rebuild and verify the Sign in with Apple capability is enabled."
#endif
        }

        return error.localizedDescription
    }
}
