import Foundation
import UIKit

enum EntitlementExpiryDisposition: Equatable, Sendable {
    case keepWithoutWake
    case rearm(after: TimeInterval)
    case clearProof
}

enum EntitlementExpiryReducer {
    static func disposition(
        currentReadyLease: IdentityLease?,
        proof: EntitlementProof?,
        now: Date?
    ) -> EntitlementExpiryDisposition {
        guard let proof else { return .keepWithoutWake }
        guard proof.lease == currentReadyLease else { return .clearProof }
        guard proof.isActive, let expirationDate = proof.expirationDate else {
            return .keepWithoutWake
        }
        guard let now else { return .clearProof }
        let delay = expirationDate.timeIntervalSince(now)
        guard delay.isFinite, delay > 0 else { return .clearProof }
        return .rearm(after: delay)
    }
}

@MainActor
protocol EntitlementExpiryScheduling: AnyObject {
    func start(reevaluator: @escaping @MainActor @Sendable () -> Void)
    func replaceWake(after delay: TimeInterval)
    func cancelWake()
}

typealias EntitlementExpirySchedulerFactory = @MainActor () -> any EntitlementExpiryScheduling

private final class NotificationRegistration: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit {
        center.removeObserver(token)
    }
}

@MainActor
final class EntitlementExpiryScheduler: EntitlementExpiryScheduling {
    private let center: NotificationCenter
    private var wakeTask: Task<Void, Never>?
    private var foregroundRegistration: NotificationRegistration?
    private var timeChangeRegistration: NotificationRegistration?
    private var reevaluator: (@MainActor @Sendable () -> Void)?
    private var wakeGeneration: UInt64 = 0

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func start(reevaluator: @escaping @MainActor @Sendable () -> Void) {
        guard self.reevaluator == nil else {
            assertionFailure("EntitlementExpiryScheduler started more than once")
            return
        }
        self.reevaluator = reevaluator
        foregroundRegistration = registration(for: UIApplication.willEnterForegroundNotification)
        timeChangeRegistration = registration(for: UIApplication.significantTimeChangeNotification)
    }

    func replaceWake(after delay: TimeInterval) {
        cancelCurrentWake()
        let generation = advanceGeneration()
        guard delay.isFinite, delay > 0 else {
            signal()
            return
        }
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == self.wakeGeneration else { return }
            self.signal()
        }
    }

    func cancelWake() {
        cancelCurrentWake()
        _ = advanceGeneration()
    }

    private func registration(for name: Notification.Name) -> NotificationRegistration {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.signal() }
        }
        return NotificationRegistration(center: center, token: token)
    }

    private func signal() {
        cancelCurrentWake()
        reevaluator?()
    }

    private func cancelCurrentWake() {
        wakeTask?.cancel()
        wakeTask = nil
    }

    private func advanceGeneration() -> UInt64 {
        SubscriptionCheckedCounter.advance(&wakeGeneration, name: "expiry wake generation")
    }

    deinit {
        wakeTask?.cancel()
    }
}
