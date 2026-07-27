import AuthenticationServices
import Foundation
import Testing
@testable import Garage

/// Covers the activation-funnel events added on top of the v1 contract, and the classifier that
/// keeps provider error text out of Analytics.
@MainActor
struct ActivationFunnelAnalyticsTests {
    @Test func activationFunnelNames_areStable() {
        #expect(AnalyticsEvent.activationFunnelNames == [
            "paywall_dismissed",
            "sign_in_started",
            "sign_in_completed",
            "sign_in_failed"
        ])
    }

    @Test func allNames_areV1PlusActivationFunnel_withNoDuplicates() {
        let all = AnalyticsEvent.allNames
        #expect(all == AnalyticsEvent.v1Names + AnalyticsEvent.activationFunnelNames)
        #expect(Set(all).count == all.count, "event names must be unique")
    }

    @Test func activationDefinitions_carryTypedParametersAndSchemaVersion() {
        let events: [AnalyticsEvent] = [
            .paywallDismissed(source: .exportPDF),
            .signInStarted(provider: .apple),
            .signInCompleted(provider: .google),
            .signInFailed(provider: .apple, reason: .cancelled)
        ]

        #expect(events.map(\.definition) == [
            AnalyticsEventDefinition(name: "paywall_dismissed", parameters: [.source(.exportPDF)]),
            AnalyticsEventDefinition(name: "sign_in_started", parameters: [.provider(.apple)]),
            AnalyticsEventDefinition(name: "sign_in_completed", parameters: [.provider(.google)]),
            AnalyticsEventDefinition(
                name: "sign_in_failed",
                parameters: [.provider(.apple), .failureReason(.cancelled)]
            )
        ])

        // schema_version must be present on every event, including the new ones.
        for event in events {
            #expect(event.definition.parameters.contains(.schemaVersion(1)))
        }
    }

    /// Every paywall entry point must be able to close its own funnel, or conversion is
    /// uncomputable for whichever source is missing.
    @Test func everyPaywallSource_hasAMatchingDismissedEvent() {
        for source in PaywallSource.allCases {
            let definition = AnalyticsEvent.paywallDismissed(source: source).definition
            #expect(definition.name == "paywall_dismissed")
            #expect(definition.parameters.contains(.source(source)))
        }
    }

    @Test func firebaseParameters_areFlatScalarsOnly() {
        let params = AnalyticsEvent
            .signInFailed(provider: .google, reason: .network)
            .definition
            .firebaseParameters
        #expect(params["provider"] as? String == "google")
        #expect(params["failure_reason"] as? String == "network")
        #expect(params["schema_version"] as? Int == 1)
    }

    // MARK: - SignInFailureClassifier

    @Test func classifier_treatsCooperativeCancellationAsCancelled() {
        #expect(SignInFailureClassifier.reason(for: CancellationError()) == .cancelled)
    }

    @Test func classifier_mapsAppleCancellationToCancelled_notAFailure() {
        let error = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.Code.canceled.rawValue
        )
        #expect(SignInFailureClassifier.reason(for: error) == .cancelled)
    }

    @Test func classifier_mapsAppleInvalidResponseToCredential() {
        let error = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.Code.invalidResponse.rawValue
        )
        #expect(SignInFailureClassifier.reason(for: error) == .credential)
    }

    @Test(arguments: [
        (NSURLErrorTimedOut, SignInFailureReason.timeout),
        (NSURLErrorCancelled, SignInFailureReason.cancelled),
        (NSURLErrorNotConnectedToInternet, SignInFailureReason.network),
        (NSURLErrorNetworkConnectionLost, SignInFailureReason.network)
    ])
    func classifier_mapsURLErrors(code: Int, expected: SignInFailureReason) {
        let error = NSError(domain: NSURLErrorDomain, code: code)
        #expect(SignInFailureClassifier.reason(for: error) == expected)
    }

    @Test func classifier_mapsGoogleCancellationToCancelled() {
        let error = NSError(domain: "com.google.GIDSignIn", code: -5)
        #expect(SignInFailureClassifier.reason(for: error) == .cancelled)
    }

    @Test func classifier_mapsAppNetworkErrorToNetwork() {
        #expect(SignInFailureClassifier.reason(for: AppError.network("offline")) == .network)
    }

    @Test func classifier_mapsTimeoutCopyToTimeout() {
        let error = AppError.auth("Sign in with Apple timed out. Check your connection and try again.")
        #expect(SignInFailureClassifier.reason(for: error) == .timeout)
    }

    @Test func classifier_mapsMissingClientIDToConfiguration() {
        let error = AppError.auth(
            "Google Sign-In is missing CLIENT_ID. Redownload GoogleService-Info.plist"
        )
        #expect(SignInFailureClassifier.reason(for: error) == .configuration)
    }

    @Test func classifier_mapsMissingPresenterToConfiguration() {
        let error = AppError.auth("Google Sign-In could not find a view controller to present from.")
        #expect(SignInFailureClassifier.reason(for: error) == .configuration)
    }

    @Test func classifier_mapsUnreadableTokenToCredential() {
        let error = AppError.auth("Apple returned an unreadable identity token.")
        #expect(SignInFailureClassifier.reason(for: error) == .credential)
    }

    @Test func classifier_fallsBackToUnknown_ratherThanGuessing() {
        let error = NSError(domain: "com.example.something", code: 42)
        #expect(SignInFailureClassifier.reason(for: error) == .unknown)
    }

    /// The whole point of the classifier: a provider message containing PII must never survive
    /// into an Analytics parameter. Reasons are a closed enum, so this is structural.
    @Test func classifier_neverEchoesProviderText() {
        let leaky = AppError.auth("Sign-in failed for jonathon@example.com with token abc123xyz")
        let reason = SignInFailureClassifier.reason(for: leaky)
        #expect(SignInFailureReason.allCases.contains(reason))

        let rendered = AnalyticsEvent
            .signInFailed(provider: .google, reason: reason)
            .definition
            .firebaseParameters
            .values
            .map { String(describing: $0) }
            .joined(separator: " ")
        #expect(!rendered.contains("@example.com"))
        #expect(!rendered.contains("abc123xyz"))
    }
}
