import FirebaseFunctions
import Foundation
import Observation

/// One NHTSA recall, as sanitised by the `lookupRecalls` Cloud Function. The upstream payload is
/// never decoded directly — the function maps it to this contract, so nothing unbounded or
/// unexpected from NHTSA reaches the app.
struct RecallLookupResult: Codable, Equatable, Sendable {
    let campaignNumber: String
    let component: String?
    let summary: String?
    let remedy: String?
    let reportReceivedDate: String?
    /// NHTSA's own do-not-drive and park-outside advisories. These are the only safety-URGENT
    /// fields it publishes, and a recall carrying either is categorically different from a routine
    /// one — the UI must not flatten them together.
    let parkIt: Bool
    let parkOutside: Bool
}

struct RecallLookupResponse: Codable, Equatable, Sendable {
    let make: String
    let model: String
    let modelYear: String
    let recalls: [RecallLookupResult]
}

enum RecallLookupError: Error, Equatable {
    /// The vehicle has no VIN recorded, so there is nothing to look up.
    case vinMissing
    /// A VIN that NHTSA's decoder could not match — a typo, or a pre-1981 vehicle.
    case vinNotRecognised
}

@MainActor
protocol RecallLooking {
    func lookup(vin: String) async throws -> RecallLookupResponse
}

@MainActor
@Observable
final class RecallLookupService: RecallLooking {
    static let shared = RecallLookupService()

    /// LAZY, and that is load-bearing. `Functions.functions()` traps if `FirebaseApp.configure()`
    /// has not run — and demo and UI-test bootstraps deliberately never configure Firebase. This
    /// service is reached through `WarrantyViewModel`'s default argument, which SwiftUI evaluates
    /// when it builds `WarrantyRecallView`, so an eager `let` here crashed the whole Garage tab in
    /// those modes. Same pre-configure hazard the app already avoids for Crashlytics via
    /// NoopCrashReporter; deferring construction to first use keeps merely *having* the service
    /// free of side effects.
    /// `@ObservationIgnored` because `@Observable` rewrites stored properties into tracked
    /// computed ones, and `lazy` cannot apply to those. It is also simply true: a Functions handle
    /// is not state anyone observes.
    @ObservationIgnored private lazy var functions = Functions.functions(region: Secrets.anthroProxyRegion)
    @ObservationIgnored private let analytics: any AnalyticsTracking

    private init(analytics: any AnalyticsTracking = AnalyticsService.shared) {
        self.analytics = analytics
    }

    func lookup(vin: String) async throws -> RecallLookupResponse {
        do {
            let response = try await performLookup(vin: vin)
            analytics.track(.recallLookupSucceeded(recallCount: response.recalls.count))
            // Fired once per lookup, not once per recall: a whole check is one funnel event, not
            // one per row it happens to find.
            if response.recalls.contains(where: { $0.parkIt || $0.parkOutside }) {
                analytics.track(.recallParkAlertShown)
            }
            return response
        } catch let error as RecallLookupError {
            analytics.track(.recallLookupFailed(reason: error == .vinMissing ? .vinMissing : .vinNotRecognised))
            throw error
        } catch {
            analytics.track(.recallLookupFailed(reason: .serviceError))
            throw error
        }
    }

    private func performLookup(vin: String) async throws -> RecallLookupResponse {
        let trimmed = vin.trimmed
        // Checked here as well as server-side so an empty VIN costs no round trip and gets a
        // specific message rather than a generic invalid-argument.
        guard !trimmed.isEmpty else { throw RecallLookupError.vinMissing }

        let callable = functions.httpsCallable("lookupRecalls")
        let result: HTTPSCallableResult
        do {
            result = try await callable.call(["vin": trimmed])
        } catch {
            // The DOMAIN check is load-bearing, not ceremony: notFound is code 5, and plenty of
            // unrelated NSErrors use code 5 too. Matching on the code alone would tell someone
            // whose network dropped that their VIN has a typo, sending them to hunt for a mistake
            // that is not there. Mirrors ClaudeService/VoiceQuickAddService's classification.
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain,
               nsError.code == FunctionsErrorCode.notFound.rawValue {
                throw RecallLookupError.vinNotRecognised
            }
            throw error
        }

        guard let data = result.data as? [String: Any] else {
            throw AppError.unknown("Recall response was not a dictionary.")
        }
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(RecallLookupResponse.self, from: json)
    }
}

extension RecallLookupResult {
    /// Maps a looked-up recall onto the stored model.
    ///
    /// `status` starts as `.outstanding` because NHTSA reports what a vehicle is *subject to*, not
    /// what a particular car has had done — only the owner knows whether the work was performed.
    /// Marking it complete on their behalf would be the app asserting something it cannot know
    /// about a safety notice.
    func asRecall(vehicleId: String, id: String) -> Recall {
        Recall(
            id: id,
            vehicleId: vehicleId,
            campaignNumber: campaignNumber,
            title: component?.nilIfEmpty ?? "NHTSA recall \(campaignNumber)",
            description: summary,
            componentAffected: component,
            dateAnnounced: nil,
            status: .outstanding,
            completedDate: nil,
            completedShop: nil,
            completedOdometer: nil,
            completedReceiptPath: nil,
            recallSource: .nhtsaApi,
            notes: Self.notes(remedy: remedy, parkIt: parkIt, parkOutside: parkOutside),
            createdAt: Date.now
        )
    }

    /// Leads with the urgent advisory when there is one. A do-not-drive notice buried under a
    /// paragraph of remedy text is a notice the owner does not read in time.
    static func notes(remedy: String?, parkIt: Bool, parkOutside: Bool) -> String? {
        var parts: [String] = []
        if parkIt {
            parts.append("DO NOT DRIVE — NHTSA advises not driving this vehicle until repaired.")
        }
        if parkOutside {
            parts.append("PARK OUTSIDE — fire risk; keep away from structures until repaired.")
        }
        if let remedy = remedy?.trimmed.nilIfEmpty {
            parts.append(remedy)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
