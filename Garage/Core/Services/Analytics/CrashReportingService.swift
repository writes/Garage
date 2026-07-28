import FirebaseCrashlytics
import Foundation

/// Consent-gated Crashlytics facade (audit #14/#23). Collection is OFF by default
/// (FirebaseCrashlyticsCollectionEnabled=false in the generated Info.plist) and is enabled only
/// alongside Analytics after a profile load confirms the user's stored opt-in — the same
/// fail-closed lifecycle AppState already drives for analytics consent.
@MainActor
protocol CrashReporting {
    func setEnabled(_ enabled: Bool)
    /// Records a handled error as a Crashlytics non-fatal. `context` is a short static label
    /// (e.g. "vehicle-decode") — never user content.
    func record(_ error: Error, context: String)
    /// Appends a line to the Crashlytics in-memory log, which ships ONLY inside a subsequent
    /// crash/non-fatal report. `message` is a short static label — never user content.
    func breadcrumb(_ message: String)
}

@MainActor
final class FirebaseCrashReporter: CrashReporting {
    private var isEnabled = false

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    func record(_ error: Error, context: String) {
        guard isEnabled else { return }
        Crashlytics.crashlytics().setCustomValue(context, forKey: "context")
        Crashlytics.crashlytics().record(error: error)
    }

    func breadcrumb(_ message: String) {
        // The isEnabled guard also keeps unit tests safe: a disabled reporter never touches
        // `Crashlytics.crashlytics()`, which traps when Firebase was never configured.
        guard isEnabled else { return }
        Crashlytics.crashlytics().log(message)
    }
}

@MainActor
final class NoopCrashReporter: CrashReporting {
    func setEnabled(_: Bool) {}

    func record(_: Error, context _: String) {}

    func breadcrumb(_: String) {}
}

@MainActor
enum CrashReporter {
    static let shared: any CrashReporting = {
#if DEBUG
        if AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode {
            return NoopCrashReporter()
        }
#endif
        return FirebaseCrashReporter()
    }()
}
