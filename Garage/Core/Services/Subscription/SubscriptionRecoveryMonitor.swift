import Foundation
import Network
import UIKit

@MainActor
final class RecoverySubscriptionToken {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    isolated deinit { onCancel?() }

    func cancel() {
        let action = onCancel
        onCancel = nil
        action?()
    }
}

@MainActor
protocol NetworkPathEventSource: AnyObject {
    func subscribe(
        _ handler: @escaping @Sendable (NetworkPathVerdict) -> Void
    ) -> RecoverySubscriptionToken
}

@MainActor
protocol ForegroundEventSource: AnyObject {
    func subscribe(
        _ handler: @escaping @Sendable () -> Void
    ) -> RecoverySubscriptionToken
}

@MainActor
final class SubscriptionRecoveryMonitor {
    private let pathSource: any NetworkPathEventSource
    private let foregroundSource: any ForegroundEventSource
    private let retry: @MainActor @Sendable () -> Void
    private var pathToken: RecoverySubscriptionToken?
    private var foregroundToken: RecoverySubscriptionToken?
    private var lastVerdict: NetworkPathVerdict?
    private var activeGeneration: UInt64 = 0

    init(
        pathSource: any NetworkPathEventSource,
        foregroundSource: any ForegroundEventSource,
        retry: @escaping @MainActor @Sendable () -> Void
    ) {
        self.pathSource = pathSource
        self.foregroundSource = foregroundSource
        self.retry = retry
    }

    func start() {
        guard pathToken == nil, foregroundToken == nil else { return }
        let generation = advanceGeneration()
        pathToken = pathSource.subscribe { [weak self] verdict in
            Task { @MainActor [weak self] in
                self?.receive(verdict, generation: generation)
            }
        }
        foregroundToken = foregroundSource.subscribe { [weak self] in
            Task { @MainActor [weak self] in
                self?.receiveForeground(generation: generation)
            }
        }
    }

    func cancel() {
        pathToken?.cancel()
        foregroundToken?.cancel()
        pathToken = nil
        foregroundToken = nil
        lastVerdict = nil
        _ = advanceGeneration()
    }

    private func receive(_ verdict: NetworkPathVerdict, generation: UInt64) {
        guard generation == activeGeneration else { return }
        let shouldRetry = RecoveryEdgeReducer.isReconnectEdge(
            previous: lastVerdict,
            new: verdict
        )
        lastVerdict = verdict
        if shouldRetry { retry() }
    }

    private func receiveForeground(generation: UInt64) {
        guard generation == activeGeneration else { return }
        retry()
    }

    private func advanceGeneration() -> UInt64 {
        SubscriptionCheckedCounter.advance(&activeGeneration, name: "recovery generation")
    }
}

@MainActor
final class LiveNetworkPathEventSource: NetworkPathEventSource {
    private let queue = DispatchQueue(label: "com.garage.subscription.network-path")

    func subscribe(
        _ handler: @escaping @Sendable (NetworkPathVerdict) -> Void
    ) -> RecoverySubscriptionToken {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            switch path.status {
            case .satisfied:
                handler(.satisfied)
            case .unsatisfied, .requiresConnection:
                handler(.unsatisfied)
            @unknown default:
                handler(.unknown)
            }
        }
        monitor.start(queue: queue)
        return RecoverySubscriptionToken { monitor.cancel() }
    }
}

@MainActor
final class LiveForegroundEventSource: ForegroundEventSource {
    private let center: NotificationCenter

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func subscribe(
        _ handler: @escaping @Sendable () -> Void
    ) -> RecoverySubscriptionToken {
        let token = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in handler() }
        return RecoverySubscriptionToken { [center] in center.removeObserver(token) }
    }
}
