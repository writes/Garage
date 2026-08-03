import Foundation
import Testing
@testable import Garage

/// AppState owns the account-level AI consent record (App Review 5.1.2(i)). These pin the three
/// properties the gate depends on: a grant is a PARTIAL write, a revoke really clears the field so
/// the next AI use re-prompts, and a failed write never leaves the app claiming consent it does
/// not have.
@MainActor
struct AppStateAIConsentTests {
    private func makeState(store: any ProfileStore) -> AppState {
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        return AppState(
            authService: AuthService(testUID: "user", analytics: analytics),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: CrashReporterSpy(),
            profileStore: store
        )
    }

    @Test func grantWritesOnlyTheConsentFieldAndFlipsTheGate() async {
        let store = AIConsentSpyStore(fields: ["analyticsOptOut": .boolean(true)])
        let state = makeState(store: store)
        await state.bootstrap()
        #expect(!state.hasGrantedAIConsent)

        let granted = Date(timeIntervalSince1970: 1_700_000_000)
        let didGrant = await state.setAIConsentGranted(true, now: granted)

        #expect(didGrant)
        #expect(state.hasGrantedAIConsent)
        #expect(state.aiConsentGrantedAt == granted)
        #expect(store.fieldWrites == [["aiConsentGrantedAt": .string("2023-11-14T22:13:20Z")]])
    }

    /// The Settings revoke: the stored field is explicitly emptied (not just dropped locally), so a
    /// reload on any device reads "never granted" and the first-use gate presents again.
    @Test func revokeClearsTheStoredFieldAndReArmsThePrompt() async {
        let store = AIConsentSpyStore(fields: ["aiConsentGrantedAt": .string("2023-11-14T22:13:20Z")])
        let state = makeState(store: store)
        await state.bootstrap()
        #expect(state.hasGrantedAIConsent)

        let didRevoke = await state.setAIConsentGranted(false)

        #expect(didRevoke)
        #expect(!state.hasGrantedAIConsent)
        #expect(store.fieldWrites.last == ["aiConsentGrantedAt": .string("")])
        #expect(store.storedFields["aiConsentGrantedAt"] == .string(""))

        let gate = AIConsentGate()
        let ranImmediately = await gate.run(isGranted: state.hasGrantedAIConsent) {}

        #expect(!ranImmediately)
        #expect(gate.isPresenting)
    }

    /// A reloaded profile must agree with the revoke — the stored empty string is the wire shape
    /// the model has to read back as "not granted".
    @Test func revokeSurvivesAProfileReload() async {
        let store = AIConsentSpyStore(fields: ["aiConsentGrantedAt": .string("2023-11-14T22:13:20Z")])
        let state = makeState(store: store)
        await state.bootstrap()
        await state.setAIConsentGranted(false)

        await state.bootstrap()

        #expect(!state.hasGrantedAIConsent)
    }

    @Test func aFailedWriteRollsTheLocalProfileBack() async {
        let store = AIConsentSpyStore(fields: ["analyticsOptOut": .boolean(true)], saveError: AIConsentStoreError.save)
        let state = makeState(store: store)
        await state.bootstrap()

        let didGrant = await state.setAIConsentGranted(true)

        #expect(!didGrant)
        #expect(!state.hasGrantedAIConsent, "a write that never landed must not read back as consent")
    }

    @Test func signedOutStateCannotRecordConsent() async {
        let store = AIConsentSpyStore(fields: [:])
        let analytics = AnalyticsSpy()
        let purchaseService = PurchaseService(testIsPro: false)
        let state = AppState(
            authService: AuthService(testUID: nil, analytics: analytics),
            vehicleService: VehicleService(testVehicles: [], purchaseService: purchaseService),
            purchaseService: purchaseService,
            analytics: analytics,
            crashReporter: CrashReporterSpy(),
            profileStore: store
        )

        let didGrant = await state.setAIConsentGranted(true)

        #expect(!didGrant)
        #expect(store.fieldWrites.isEmpty)
    }
}

@MainActor
private final class AIConsentSpyStore: ProfileStore {
    private(set) var storedFields: ProfileFields
    private(set) var fieldWrites: [ProfileFields] = []
    private let saveError: Error?

    init(fields: ProfileFields, saveError: Error? = nil) {
        storedFields = fields
        self.saveError = saveError
    }

    func loadProfile(uid _: String) async throws -> ProfileFields? {
        storedFields
    }

    func saveProfile(_ fields: ProfileFields, uid _: String) async throws {
        if let saveError { throw saveError }
        storedFields = fields
    }

    /// Kept separate from `saveProfile` so a test can prove the consent write is PARTIAL — the
    /// default protocol forwarding would hide a full-document write.
    func saveProfileFields(_ fields: ProfileFields, uid _: String) async throws {
        fieldWrites.append(fields)
        if let saveError { throw saveError }
        storedFields.merge(fields) { _, replacement in replacement }
    }
}

private enum AIConsentStoreError: Error {
    case save
}
