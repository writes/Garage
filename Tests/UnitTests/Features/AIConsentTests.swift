import Foundation
import Testing
@testable import Garage

/// The first-use gate's state machine. It is deliberately store-free, so these run the real
/// admission decisions without a view, a profile, or a network.
@MainActor
struct AIConsentGateTests {
    @Test func unconsentedRunParksTheActionAndRaisesThePrompt() async {
        let gate = AIConsentGate()
        var didRun = false

        let ranImmediately = await gate.run(isGranted: false) { didRun = true }

        #expect(!ranImmediately)
        #expect(gate.isPresenting)
        #expect(!didRun, "the upload must not start before consent is collected")
    }

    @Test func consentedRunPassesStraightThroughWithNoPrompt() async {
        let gate = AIConsentGate()
        var didRun = false

        let ranImmediately = await gate.run(isGranted: true) { didRun = true }

        #expect(ranImmediately)
        #expect(!gate.isPresenting)
        #expect(didRun)
    }

    /// "Not Now" is the no-side-effects exit: nothing uploaded, and the parked action is dropped
    /// rather than left to fire on a later presentation of the same gate.
    @Test func declineDropsTheParkedActionSoNoLaterConfirmCanRunIt() async {
        let gate = AIConsentGate()
        var didRun = false
        await gate.run(isGranted: false) { didRun = true }

        gate.decline()
        await gate.confirm(persist: { true })

        #expect(!gate.isPresenting)
        #expect(!didRun)
    }

    /// Continue must not hold the parked action hostage to the consent write: the action the user
    /// asked for (start the mic, send the receipt) runs while the write is still in flight. A
    /// serialized implementation leaves the action dead behind a whole network round-trip — this
    /// pins the concurrent contract by making the write slower than the action.
    @Test func confirmRunsTheParkedActionWithoutWaitingOnTheWrite() async {
        let gate = AIConsentGate()
        var order: [String] = []
        await gate.run(isGranted: false) { order.append("action") }

        await gate.confirm(persist: {
            try? await Task.sleep(nanoseconds: 100_000_000)
            order.append("write-landed")
            return true
        })

        #expect(order == ["action", "write-landed"])
        #expect(!gate.isPresenting)
    }

    /// The tap IS the consent. A failed write only means the prompt returns next time — it must
    /// never strand the action the user just authorized.
    @Test func confirmStillRunsTheActionWhenTheWriteFails() async {
        let gate = AIConsentGate()
        var didRun = false
        await gate.run(isGranted: false) { didRun = true }

        await gate.confirm(persist: { false })

        #expect(didRun)
    }

    /// Re-entry after a decline must present again — that is the "revoke → re-prompt" contract
    /// seen from the gate's side.
    @Test func aDeclinedGateRaisesThePromptAgainOnTheNextAttempt() async {
        let gate = AIConsentGate()
        await gate.run(isGranted: false) {}
        gate.decline()

        let ranImmediately = await gate.run(isGranted: false) {}

        #expect(!ranImmediately)
        #expect(gate.isPresenting)
    }
}

@MainActor
struct UserProfileAIConsentTests {
    @Test func consentRoundTripsThroughProfileFields() {
        let granted = Date(timeIntervalSince1970: 1_700_000_000)
        var profile = UserProfile(id: "u", profileFields: [:])
        #expect(profile.aiConsentGrantedAt == nil)
        profile.aiConsentGrantedAt = granted

        let fields = profile.profileFields

        #expect(fields["aiConsentGrantedAt"] == .string("2023-11-14T22:13:20Z"))
        #expect(UserProfile(id: "u", profileFields: fields).aiConsentGrantedAt == granted)
    }

    /// The two shapes a revoked account can have on the wire.
    @Test func missingOrEmptyConsentReadsAsNotGranted() {
        #expect(UserProfile(id: "u", profileFields: [:]).aiConsentGrantedAt == nil)
        #expect(UserProfile(id: "u", profileFields: ["aiConsentGrantedAt": .string("")]).aiConsentGrantedAt == nil)
    }

    @Test func unparseableConsentReadsAsNotGranted() {
        let fields: ProfileFields = ["aiConsentGrantedAt": .string("whenever")]
        #expect(UserProfile(id: "u", profileFields: fields).aiConsentGrantedAt == nil)
    }
}

/// The full-save contract for a field this screen does NOT own: `save()` writes only
/// `formOwnedFields`, and the store merges, so the consent key is preserved by OMISSION — neither
/// wiped (the original themeID bug class) nor resurrected from a stale cached copy (the
/// 2026-08-03 cross-check finding: revoke in Settings, then save a name edit on a still-loaded
/// Profile screen, and the cached grant silently un-revoked the account).
@MainActor
struct ProfileViewModelAIConsentTests {
    private func makeViewModel(store: any ProfileStore) -> ProfileViewModel {
        ProfileViewModel(store: store, userID: { "user" }, isDemoMode: false, automaticallyLoad: false)
    }

    @Test func fullSavePreservesAIConsentInsteadOfWipingIt() async {
        let store = ConsentProfileStore(fields: ["aiConsentGrantedAt": .string("2023-11-14T22:13:20Z")])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        // Pre-save sanity via the store, not a VM accessor: the VM deliberately no longer exposes
        // consent — AppState owns the read, and this screen neither shows nor writes it.
        let loaded = UserProfile(id: "user", profileFields: store.profile ?? [:])
        #expect(loaded.aiConsentGrantedAt == Date(timeIntervalSince1970: 1_700_000_000))

        viewModel.name = "Ada Driver"
        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(store.profile?["aiConsentGrantedAt"] == .string("2023-11-14T22:13:20Z"))
        #expect(store.profile?["name"] == .string("Ada Driver"))
    }

    @Test func fullSaveOfARevokedProfileKeepsItRevoked() async {
        let store = ConsentProfileStore(fields: ["name": .string("Ada Driver")])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        let didSave = await viewModel.save()

        #expect(didSave)
        // The consent key is never part of a form save — a never-granted account stays that way.
        #expect(store.savePayloads.allSatisfy { $0["aiConsentGrantedAt"] == nil })
        #expect(UserProfile(id: "user", profileFields: store.profile ?? [:]).aiConsentGrantedAt == nil)
    }

    /// THE cross-check scenario: consent is revoked (by Settings/AppState, i.e. behind this
    /// screen's back) while a loaded Profile screen still caches the old grant. Saving a name
    /// edit from that stale screen must not write the grant back.
    @Test func settingsRevokeSurvivesAStaleProfileScreenSave() async throws {
        let store = ConsentProfileStore(fields: ["aiConsentGrantedAt": .string("2023-11-14T22:13:20Z")])
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        // The Settings revoke lands as the partial field write AppState performs.
        try await store.saveProfile(["aiConsentGrantedAt": .string("")], uid: "user")
        viewModel.name = "Ada Driver"
        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(store.profile?["name"] == .string("Ada Driver"))
        #expect(UserProfile(id: "user", profileFields: store.profile ?? [:]).aiConsentGrantedAt == nil)
    }
}
