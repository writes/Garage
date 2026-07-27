import Foundation

/// Supporting types for the analytics contract: the closed enums every event parameter is drawn
/// from, plus the definition/parameter plumbing.
///
/// Split out of AnalyticsService.swift purely for file length. The important property is that
/// `AnalyticsParameter` admits only `Int` and enums declared here — a call site cannot pass a
/// caller-supplied String, so a UID, email, VIN or provider error message cannot structurally
/// reach Analytics. See docs/developer/ANALYTICS_CONTRACT.md.

enum PaywallSource: String, CaseIterable, Equatable, Sendable {
    case settings
    case garage
    case reminders
    case exportPDF = "export_pdf"
    case stats
    case themePicker = "theme_picker"
    case attachments
}

enum AnalyticsProductID: String, CaseIterable, Equatable, Sendable {
    case monthly = "garage_pro_monthly"
    case annual = "garage_pro_annual"

    init?(storeProductIdentifier: String) {
        switch storeProductIdentifier {
        case Constants.monthlyPlanIdentifier:
            self = .monthly
        case Constants.annualPlanIdentifier:
            self = .annual
        default:
            return nil
        }
    }
}

enum OilAnalysisQuotaDeniedReason: String, CaseIterable, Equatable, Sendable {
    case freeLifetimeExhausted = "free_lifetime_exhausted"
    case proDailyExhausted = "pro_daily_exhausted"
}

struct AnalyticsEventDefinition: Equatable, Sendable {
    let name: String
    let parameters: [AnalyticsParameter]

    init(name: String, parameters: [AnalyticsParameter] = []) {
        self.name = name
        self.parameters = [.schemaVersion(1)] + parameters
    }

    var firebaseParameters: [String: Any] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.firebaseValue) })
    }
}

enum AnalyticsParameter: Equatable, Sendable {
    case schemaVersion(Int)
    case entryType(EntryType)
    case source(PaywallSource)
    case productID(AnalyticsProductID)
    case entryCount(Int)
    case reason(OilAnalysisQuotaDeniedReason)
    case provider(AuthProvider)
    case failureReason(SignInFailureReason)
    case form(FormKind)

    fileprivate var name: String {
        switch self {
        case .schemaVersion: return "schema_version"
        case .entryType: return "entry_type"
        case .source: return "source"
        case .productID: return "product_id"
        case .entryCount: return "entry_count"
        case .reason: return "reason"
        case .provider: return "provider"
        case .failureReason: return "failure_reason"
        case .form: return "form"
        }
    }

    fileprivate var firebaseValue: Any {
        switch self {
        case .schemaVersion(let value), .entryCount(let value): return value
        case .entryType(let value): return value.rawValue
        case .source(let value): return value.rawValue
        case .productID(let value): return value.rawValue
        case .reason(let value): return value.rawValue
        case .provider(let value): return value.rawValue
        case .failureReason(let value): return value.rawValue
        case .form(let value): return value.rawValue
        }
    }
}

enum AuthProvider: String, CaseIterable, Equatable, Sendable {
    case apple
    case google
}

/// Which sheet a `form_opened` event refers to. Records what ACTUALLY opened, not what was
/// requested — `AppRouter.present` redirects entry sheets to vehicle creation when the account
/// has no vehicles, and attributing that open to `entry` would misreport the funnel.
///
/// The paywall is deliberately absent: it already reports `paywall_viewed`, and adding it here
/// would double-count the same impression.
enum FormKind: String, CaseIterable, Equatable, Sendable {
    case vehicle
    case entryPicker = "entry_picker"
    case entry
    case voiceQuickAdd = "voice_quick_add"
    case export
}

/// Closed set of sign-in failure causes. Deliberately coarse: it exists to separate "the user
/// changed their mind" from "the app is broken", which are opposite signals that a single
/// `sign_in_failed` count would conflate. `cancelled` is the expected majority and is NOT an error.
enum SignInFailureReason: String, CaseIterable, Equatable, Sendable {
    /// User backed out of the provider sheet. Expected, not a defect.
    case cancelled
    /// Connectivity or provider reachability.
    case network
    /// Timed out waiting on the provider (the Apple flow enforces its own deadline).
    case timeout
    /// Missing or invalid client configuration — a build or console misconfiguration, and the one
    /// reason here that always indicates a real defect.
    case configuration
    /// Provider returned successfully but the credential was unusable.
    case credential
    case unknown
}
