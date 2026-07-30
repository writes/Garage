import SwiftUI

/// Owns the app's ONE live vehicles listener, for the lifetime of the authenticated session.
///
/// This task used to live in `VehicleSwitcher`, which is instantiated by FIVE screens (the
/// Dashboard hero card, Log, Garage, Stats and Settings). The TabView appears them all, so every
/// launch opened a vehicles listener per switcher and re-opened them as tabs came and went — on
/// top of `AppState.bootstrap`'s one-time fetch of the same collection. Hosting the listener once,
/// above the TabView, makes it exactly one listener whose lifetime is the session rather than
/// whichever screen happens to be on screen (which matters more now that tab content is built
/// lazily), and lets the bootstrap fetch go away entirely: the listener's first snapshot IS the
/// initial load.
///
/// The sync PROBE deliberately keeps its own short-lived listener. It exists to force a fresh
/// post-acknowledgement server observation, which this long-lived listener structurally cannot
/// deliver — its query is already synced, so Firestore has no further snapshot to send. Feeding
/// the probe from this stream instead would leave the badge stuck on "Checking sync…" whenever the
/// primary server snapshot lands before the write barrier is acknowledged.
struct VehicleSyncHost: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var syncService = SyncService.shared

    private var activeUID: String? {
        AppRuntime.isLocalDemoMode ? AppRuntime.demoUserId : AuthService.shared.uid
    }

    func body(content: Content) -> some View {
        content.task(id: activeUID) { await runSession() }
    }

    private func runSession() async {
        guard let uid = activeUID else { return }

        let session = syncService.activateSession(uid: uid)
        defer {
            // A same-account view/task restart retains its token and monitor. Auth changes do
            // the cancel-before-invalidate transition in the reducer.
            let currentUID = activeUID
            if currentUID == nil || currentUID != session.uid {
                syncService.deactivateSession(session)
            }
        }

        bindProbeStarter(session: session)

        // Created before the barrier starts, exactly as when this lived in the switcher: the
        // stream registers its Firestore listener at construction and buffers until consumed.
        let stream = VehicleService.shared.listenToVehicles()
        if !AppRuntime.isLocalDemoMode {
            syncService.bindBarrierStarter(session: session) { [weak syncService] activeSession in
                guard let syncService else { return }
                syncService.beginWriteBarrier(
                    session: activeSession,
                    using: FirestoreService.shared.startWriteBarrier
                )
            }
            // This is intentionally non-awaiting; it is a relaunch acknowledgement boundary.
            syncService.beginWriteBarrier(
                session: session,
                using: FirestoreService.shared.startWriteBarrier
            )
        }

        await consume(stream, session: session)
    }

    private func consume(_ stream: VehicleService.VehicleStream, session: SyncSessionToken) async {
        do {
            for try await envelope in stream {
                if Task.isCancelled { return }
                syncService.recordPrimarySnapshot(envelope, session: session)
                // The decoded vehicles were previously discarded here (audit #9) — this is
                // what keeps AppState.vehicles/currentVehicle live: edits from other
                // devices/screens land without a manual refresh.
                appState.applyVehicleSnapshot(envelope)
            }
        } catch {
            if Task.isCancelled { return }
            if error is CancellationError { return }
            syncService.recordFailure(session: session, message: error.localizedDescription)
        }
        // The listener is now the ONLY thing that flips hasCompletedInitialVehicleLoad, so a
        // listener that fails before its first snapshot would otherwise leave the Dashboard on its
        // awaiting-first-load spinner forever. One fetch, only on that path — never on a launch
        // the listener served.
        if !Task.isCancelled, !appState.hasCompletedInitialVehicleLoad {
            await appState.refreshVehicles()
        }
    }

    private func bindProbeStarter(session: SyncSessionToken) {
        syncService.bindProbeStarter(session: session) { [weak syncService] token in
            Task { @MainActor [weak syncService] in
                defer { syncService?.finishProbe(token) }
                guard let syncService else { return }
                do {
                    for try await envelope in VehicleService.shared.listenToVehicles() {
                        if Task.isCancelled { return }
                        switch syncService.reduceProbe(.envelope(envelope), token: token) {
                        case .continueListening: continue
                        case .stopListening, .ignored: return
                        }
                    }
                    if !Task.isCancelled {
                        _ = syncService.reduceProbe(
                            .failure(VehicleListenerError(
                                message: "The vehicle sync listener ended unexpectedly."
                            )),
                            token: token
                        )
                    }
                } catch {
                    if Task.isCancelled || error is CancellationError { return }
                    let listenerError = (error as? VehicleListenerError)
                        ?? VehicleListenerError(message: error.localizedDescription)
                    _ = syncService.reduceProbe(.failure(listenerError), token: token)
                }
            }
        }
    }
}

extension View {
    /// Apply exactly ONCE, to the authenticated shell — a second host is a second listener.
    func vehicleSyncHost() -> some View {
        modifier(VehicleSyncHost())
    }
}
