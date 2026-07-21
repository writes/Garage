import SwiftUI

struct VehicleSwitcher: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var syncService = SyncService.shared

    private var activeUID: String? {
        AppRuntime.isLocalDemoMode ? AppRuntime.demoUserId : AuthService.shared.uid
    }

    var body: some View {
        Menu {
            ForEach(appState.vehicles) { vehicle in
                Button(vehicle.displayName) {
                    appState.selectVehicle(vehicle)
                }
            }
            Divider()
            Button("Add Vehicle") {
                router.present(.vehicleForm)
            }
            .accessibilityIdentifier("vehicle.switcher.add")
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "car.2.fill")
                Text(appState.currentVehicle?.displayName ?? "Add your first vehicle")
                    .lineLimit(1)
                BadgeView(
                    title: syncService.presentationState.label,
                    color: badgeColor
                )
                    .accessibilityIdentifier("sync.badge")
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityLabel("Vehicle switcher")
        .accessibilityValue(appState.currentVehicle?.id ?? "")
        .accessibilityIdentifier("vehicle.switcher")
        .task(id: activeUID) {
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

            do {
                for try await envelope in stream {
                    if Task.isCancelled { return }
                    syncService.recordPrimarySnapshot(envelope, session: session)
                }
            } catch {
                if Task.isCancelled { return }
                if error is CancellationError { return }
                syncService.recordFailure(session: session, message: error.localizedDescription)
            }
        }
    }

    private var badgeColor: Color {
        switch syncService.presentationState {
        case .upToDate: return Theme.Colors.success
        case .syncing, .checkingSync: return Theme.Colors.accent
        case .savedOnThisIPhone, .offlineCachedData: return Theme.Colors.warning
        case .needsAttention: return Theme.Colors.error
        }
    }
}
