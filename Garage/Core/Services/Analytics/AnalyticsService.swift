import FirebaseAnalytics
import Foundation

@MainActor
protocol AnalyticsTracking: AnyObject {
    func track(_ event: AnalyticsEvent)
    func setEnabled(_ enabled: Bool)
    /// Fails closed after a user tries to revoke consent but persistence cannot confirm it.
    /// The suppression deliberately lasts for the current app session.
    func suppressCollectionForCurrentSession()
}

extension AnalyticsTracking {
    func suppressCollectionForCurrentSession() {
        setEnabled(false)
    }
}

/// The complete v1 product-event contract.
///
/// Associated values deliberately use only closed enums and numeric counts. That makes it
/// impossible for a call site to send a UID, email address, VIN, or free-form text as an
/// Analytics parameter. The `first_*` events use a successful post-insert `count == 1`
/// check, which is a per-account-per-device approximation in v1 rather than global dedupe.
enum AnalyticsEvent: Equatable, Sendable {
    case firstVehicleAdded
    case firstEntryAdded(entryType: EntryType)
    case paywallViewed(source: PaywallSource)
    /// A non-authoritative client signal; server-side revenue joins remain the revenue truth.
    case purchaseCompleted(productID: AnalyticsProductID)
    case purchaseRestored
    case exportCSV(entryCount: Int)
    case exportPDF(entryCount: Int)
    case oilAnalysisRequested
    case oilAnalysisSucceeded
    case oilAnalysisQuotaDenied(reason: OilAnalysisQuotaDeniedReason)

    static let v1Names = [
        "first_vehicle_added",
        "first_entry_added",
        "paywall_viewed",
        "purchase_completed",
        "purchase_restored",
        "export_csv",
        "export_pdf",
        "oil_analysis_requested",
        "oil_analysis_succeeded",
        "oil_analysis_quota_denied"
    ]

    /// Keeps every v1 event name and parameter definition in one audited mapping.
    var definition: AnalyticsEventDefinition {
        switch self {
        case .firstVehicleAdded:
            return AnalyticsEventDefinition(name: "first_vehicle_added")
        case .firstEntryAdded(let entryType):
            return AnalyticsEventDefinition(
                name: "first_entry_added",
                parameters: [.entryType(entryType)]
            )
        case .paywallViewed(let source):
            return AnalyticsEventDefinition(
                name: "paywall_viewed",
                parameters: [.source(source)]
            )
        case .purchaseCompleted(let productID):
            return AnalyticsEventDefinition(
                name: "purchase_completed",
                parameters: [.productID(productID)]
            )
        case .purchaseRestored:
            return AnalyticsEventDefinition(name: "purchase_restored")
        case .exportCSV(let entryCount):
            return AnalyticsEventDefinition(
                name: "export_csv",
                parameters: [.entryCount(max(0, entryCount))]
            )
        case .exportPDF(let entryCount):
            return AnalyticsEventDefinition(
                name: "export_pdf",
                parameters: [.entryCount(max(0, entryCount))]
            )
        case .oilAnalysisRequested:
            return AnalyticsEventDefinition(name: "oil_analysis_requested")
        case .oilAnalysisSucceeded:
            return AnalyticsEventDefinition(name: "oil_analysis_succeeded")
        case .oilAnalysisQuotaDenied(let reason):
            return AnalyticsEventDefinition(
                name: "oil_analysis_quota_denied",
                parameters: [.reason(reason)]
            )
        }
    }
}

enum PaywallSource: String, CaseIterable, Equatable, Sendable {
    case settings
    case garage
    case reminders
    case exportPDF = "export_pdf"
    case stats
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

    fileprivate var name: String {
        switch self {
        case .schemaVersion: return "schema_version"
        case .entryType: return "entry_type"
        case .source: return "source"
        case .productID: return "product_id"
        case .entryCount: return "entry_count"
        case .reason: return "reason"
        }
    }

    fileprivate var firebaseValue: Any {
        switch self {
        case .schemaVersion(let value), .entryCount(let value): return value
        case .entryType(let value): return value.rawValue
        case .source(let value): return value.rawValue
        case .productID(let value): return value.rawValue
        case .reason(let value): return value.rawValue
        }
    }
}

@MainActor
final class FirebaseAnalyticsService: AnalyticsTracking {
    private var isEnabled = false
    private var isCollectionSuppressedForCurrentSession = false

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        let definition = event.definition
        Analytics.logEvent(definition.name, parameters: definition.firebaseParameters)
    }

    func setEnabled(_ enabled: Bool) {
        let effectiveEnabled = enabled && !isCollectionSuppressedForCurrentSession
        isEnabled = effectiveEnabled
        Analytics.setAnalyticsCollectionEnabled(effectiveEnabled)
    }

    func suppressCollectionForCurrentSession() {
        isCollectionSuppressedForCurrentSession = true
        setEnabled(false)
    }
}

@MainActor
final class NoopAnalyticsService: AnalyticsTracking {
    func track(_: AnalyticsEvent) {}

    func setEnabled(_: Bool) {}
}

@MainActor
enum AnalyticsService {
    static let shared: any AnalyticsTracking = {
#if DEBUG
        if AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode {
            return NoopAnalyticsService()
        }
#endif
        return FirebaseAnalyticsService()
    }()
}

// WAVE-1 iOS-6L: Oil-analysis event call sites land with the typed AI wiring work.
