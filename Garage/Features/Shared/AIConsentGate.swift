import Observation
import SwiftUI

/// Presentation state for the one-time AI consent prompt (App Review 5.1.2(i)).
///
/// It holds the action the user actually asked for — start dictating, send this receipt — so that
/// granting consent continues that action instead of making the user tap twice. Declining drops
/// the action and writes nothing, which is what makes "Not Now" side-effect free.
///
/// The gate deliberately takes `isGranted` per call rather than owning a profile dependency: the
/// account answer lives on `AppState`, and keeping this type a pure state machine is what lets the
/// gate be exercised without a view or a store.
@MainActor
@Observable
final class AIConsentGate {
    private(set) var isPresenting = false
    private var pendingAction: (@MainActor () async -> Void)?

    /// Runs `action` straight through when consent is already on record; otherwise parks it and
    /// raises the prompt. Returns whether the action ran immediately.
    @discardableResult
    func run(isGranted: Bool, action: @escaping @MainActor () async -> Void) async -> Bool {
        guard !isGranted else {
            await action()
            return true
        }
        pendingAction = action
        isPresenting = true
        return false
    }

    /// Continue: records the grant and runs the parked action CONCURRENTLY. The action runs even
    /// when the write fails — the user's tap is the consent, and an unrecorded grant only means
    /// the prompt returns next time.
    func confirm(persist: @escaping @MainActor () async -> Bool) async {
        // Claim the action BEFORE dismissing: lowering `isPresenting` fires the sheet binding's
        // dismissal path, which calls `decline()` and would otherwise drop what we are about to run.
        let action = pendingAction
        pendingAction = nil
        isPresenting = false
        // Concurrent, not sequential: persist flips the local grant before its first suspension,
        // and serializing left the parked action (the mic the user asked for) dead behind a whole
        // network round-trip after Continue.
        async let persisted = persist()
        await action?()
        _ = await persisted
    }

    /// Not Now, or a swipe-dismiss: no write, no upload, nothing left behind.
    func decline() {
        pendingAction = nil
        isPresenting = false
    }
}

extension View {
    /// Attaches the first-use consent prompt to a gated surface. `persist` records the grant and
    /// reports whether it stuck.
    func aiConsentPrompt(
        _ gate: AIConsentGate,
        persist: @escaping @MainActor () async -> Bool
    ) -> some View {
        sheet(
            isPresented: Binding(
                get: { gate.isPresenting },
                set: { isPresented in
                    guard !isPresented else { return }
                    gate.decline()
                }
            )
        ) {
            AIConsentSheet(
                continueTapped: { Task { await gate.confirm(persist: persist) } },
                notNowTapped: { gate.decline() }
            )
        }
    }
}
