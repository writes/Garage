import FirebaseFunctions
import Foundation

/// Fetches the server registry override (`experimentConfig` callable — App Check only, no
/// auth: the kill switch must be reachable from the first paint, before sign-in exists).
/// Fire-and-forget from the app shell; a failure leaves the bundled/cached registry in
/// force, which is always safe (control-biased).
@MainActor
final class ExperimentConfigService {
    static let shared = ExperimentConfigService()

    /// Lazy handle: `Functions.functions()` before `FirebaseApp.configure()` is the
    /// preconfigure launch-crash class — demo/UI-test runs must never construct it (the
    /// DEBUG guard in `fetchOverride` returns before this is ever touched there).
    private lazy var functions = Functions.functions()

    /// Decodes the callable's `{definitions: [...]}` into the client registry shape.
    /// Unknown ids/arms were already dropped server-side; anything undecodable here yields
    /// nil (keep the current registry) rather than an empty override (which would wrongly
    /// erase a cached kill switch).
    func fetchOverride() async -> [ExperimentDefinition]? {
#if DEBUG
        if AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode { return nil }
#endif
        do {
            let result = try await functions.httpsCallable("experimentConfig").call()
            let data = try JSONSerialization.data(withJSONObject: result.data)
            let payload = try JSONDecoder().decode(OverridePayload.self, from: data)
            return payload.definitions
        } catch {
            return nil
        }
    }

    private struct OverridePayload: Decodable {
        let definitions: [ExperimentDefinition]
    }
}
