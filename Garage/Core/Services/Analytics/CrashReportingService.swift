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
    /// Stamps the experiment arm/epoch onto every subsequent report so the per-arm crash-free
    /// guardrail is measurable in the Crashlytics console. Both values are closed-enum /
    /// bounded-int experiment state, never identity.
    func setExperimentContext(arm: ExperimentArm, epoch: Int)
}

@MainActor
final class FirebaseCrashReporter: CrashReporting {
    static let armKey = "design_arm"
    static let epochKey = "experiment_epoch"

    /// Owns the enabled flag: the experiment keys need a hold-until-consent rule that a bare
    /// bool cannot express, and two copies of "is collection on" would eventually disagree.
    private var experimentKeys = ExperimentCrashKeyGate()

    private var isEnabled: Bool { experimentKeys.isEnabled }

    func setEnabled(_ enabled: Bool) {
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
        write(experimentKeys.setEnabled(enabled))
    }

    func setExperimentContext(arm: ExperimentArm, epoch: Int) {
        write(experimentKeys.setContext(arm: arm, epoch: epoch))
    }

    private func write(_ keys: ExperimentCrashKeyGate.Keys?) {
        guard let keys else { return }
        // armValue/epochValue, never the raw optionals: see the Keys doc-comment for why a nil
        // through `setCustomValue`'s Any parameter records garbage instead of clearing.
        Crashlytics.crashlytics().setCustomValue(keys.armValue, forKey: Self.armKey)
        Crashlytics.crashlytics().setCustomValue(keys.epochValue, forKey: Self.epochKey)
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

    func setExperimentContext(arm _: ExperimentArm, epoch _: Int) {}
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
