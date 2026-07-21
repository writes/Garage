import RevenueCat
@testable import Garage

@MainActor
final class AnalyticsSpy: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var enabledValues: [Bool] = []
    private var isEnabled = false
    private var isCollectionSuppressedForCurrentSession = false

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        events.append(event)
    }

    func setEnabled(_ enabled: Bool) {
        let effectiveEnabled = enabled && !isCollectionSuppressedForCurrentSession
        isEnabled = effectiveEnabled
        enabledValues.append(effectiveEnabled)
    }

    func suppressCollectionForCurrentSession() {
        isCollectionSuppressedForCurrentSession = true
        setEnabled(false)
    }
}

@MainActor
final class PurchaseResultProbe {
    private let result: PurchaseResultData
    private(set) var calls = 0

    init(result: PurchaseResultData) {
        self.result = result
    }

    func load() async throws -> PurchaseResultData {
        calls += 1
        return result
    }
}

struct SyncPresentationLabelCase {
    let hasPendingWrites: Bool
    let connectivity: SyncConnectivity
    let expectedLabel: String

    static let all = [
        Self(hasPendingWrites: false, connectivity: .unknown, expectedLabel: "Checking log sync"),
        Self(hasPendingWrites: false, connectivity: .reachable, expectedLabel: "Checking log sync"),
        Self(hasPendingWrites: false, connectivity: .unreachable, expectedLabel: "Offline"),
        Self(hasPendingWrites: true, connectivity: .unknown, expectedLabel: "Saved on this iPhone"),
        Self(hasPendingWrites: true, connectivity: .reachable, expectedLabel: "Syncing service log"),
        Self(hasPendingWrites: true, connectivity: .unreachable, expectedLabel: "Saved on this iPhone")
    ]
}

@MainActor
final class SyncMonitorSpy: SyncConnectivityMonitoring {
    private var handler: (@MainActor @Sendable (SyncConnectivity) -> Void)?
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
    }

    func emit(_ state: SyncConnectivity) {
        handler?(state)
    }
}

@MainActor
final class SyncPassiveMonitor: SyncConnectivityMonitoring {
    func start(_ handler: @escaping @MainActor @Sendable (SyncConnectivity) -> Void) {}
    func cancel() {}
}

@MainActor
final class SyncProbeStarter {
    private(set) var tokens: [SyncProbeToken] = []
    private var tokenCountContinuations: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func start(_ token: SyncProbeToken) -> Task<Void, Never> {
        tokens.append(token)
        let readyCounts = tokenCountContinuations.keys.filter { tokens.count >= $0 }
        for count in readyCounts {
            let continuations = tokenCountContinuations.removeValue(forKey: count) ?? []
            continuations.forEach { $0.resume() }
        }
        return Task { @MainActor in }
    }

    func waitForTokens(_ count: Int) async {
        guard tokens.count < count else { return }
        await withCheckedContinuation { continuation in
            tokenCountContinuations[count, default: []].append(continuation)
        }
    }
}
