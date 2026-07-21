import Testing
@testable import Garage

@MainActor
struct SubscriptionRecoveryMonitorTests {
    @Test func reconnectReducerEmitsOnlyUnsatisfiedOrUnknownToSatisfied() {
        let cases: [ReconnectCase] = [
            ReconnectCase(previous: nil, new: .satisfied, expected: false),
            ReconnectCase(previous: .unsatisfied, new: .satisfied, expected: true),
            ReconnectCase(previous: .unknown, new: .satisfied, expected: true),
            ReconnectCase(previous: .satisfied, new: .satisfied, expected: false),
            ReconnectCase(previous: .unsatisfied, new: .unknown, expected: false),
            ReconnectCase(previous: .unknown, new: .unsatisfied, expected: false)
        ]
        for value in cases {
            let actual = RecoveryEdgeReducer.isReconnectEdge(previous: value.previous, new: value.new)
            #expect(actual == value.expected)
        }
    }

    @Test func startIsIdempotentAndCancelDisposesEachSourceOnce() {
        let source = RecoverySourceSpy()
        let monitor = SubscriptionRecoveryMonitor(
            pathSource: source,
            foregroundSource: source,
            retry: {}
        )
        monitor.start()
        monitor.start()
        #expect(source.networkHandlers.count == 1)
        #expect(source.foregroundHandlers.count == 1)
        monitor.cancel()
        monitor.cancel()
        #expect(source.networkCancellations == 1)
        #expect(source.foregroundCancellations == 1)
    }

    @Test func tokenReleaseCancelsExactlyOnceWithOrWithoutManualCancel() {
        let automatic = SubscriptionCounter()
        var automaticToken: RecoverySubscriptionToken? = RecoverySubscriptionToken {
            automatic.increment()
        }
        #expect(automaticToken != nil)
        automaticToken = nil
        #expect(automatic.value == 1)

        let manual = SubscriptionCounter()
        var manualToken: RecoverySubscriptionToken? = RecoverySubscriptionToken {
            manual.increment()
        }
        manualToken?.cancel()
        manualToken = nil
        #expect(manual.value == 1)
    }

    @Test func repeatedSatisfiedIsSuppressedAndForegroundRetries() async {
        let network = TestNetworkSource()
        let foreground = TestForegroundSource()
        let counter = RetryCounter()
        let monitor = SubscriptionRecoveryMonitor(
            pathSource: network,
            foregroundSource: foreground,
            retry: counter.increment
        )
        monitor.start()
        network.handlers[0](.unsatisfied)
        network.handlers[0](.satisfied)
        network.handlers[0](.satisfied)
        foreground.handlers[0]()
        await settleMainActor()
        #expect(counter.value == 2)
    }

    @Test func cancelRestartFencesOldGenerationAndCreatesFreshSubscriptions() async {
        let network = TestNetworkSource()
        let foreground = TestForegroundSource()
        let counter = RetryCounter()
        let monitor = SubscriptionRecoveryMonitor(
            pathSource: network,
            foregroundSource: foreground,
            retry: counter.increment
        )
        monitor.start()
        let oldNetwork = network.handlers[0]
        let oldForeground = foreground.handlers[0]
        monitor.cancel()
        monitor.start()
        let currentNetwork = network.handlers[1]
        let currentForeground = foreground.handlers[1]
        await Task.detached {
            oldNetwork(.unsatisfied)
            oldNetwork(.satisfied)
            oldForeground()
        }.value
        await Task.detached { currentNetwork(.unsatisfied) }.value
        await settleMainActor()
        await Task.detached {
            currentNetwork(.satisfied)
            currentForeground()
        }.value
        await settleMainActor()
        #expect(network.handlers.count == 2)
        #expect(foreground.handlers.count == 2)
        #expect(counter.value == 2)
    }

    private func settleMainActor() async {
        await Task.yield()
        await Task.yield()
    }
}

private struct ReconnectCase {
    let previous: NetworkPathVerdict?
    let new: NetworkPathVerdict
    let expected: Bool
}

@MainActor
private final class RetryCounter {
    private(set) var value = 0
    func increment() { MainActor.assertIsolated(); value += 1 }
}

@MainActor
private final class RecoverySourceSpy: NetworkPathEventSource, ForegroundEventSource {
    private(set) var networkHandlers: [@Sendable (NetworkPathVerdict) -> Void] = []
    private(set) var foregroundHandlers: [@Sendable () -> Void] = []
    private(set) var networkCancellations = 0
    private(set) var foregroundCancellations = 0

    func subscribe(
        _ handler: @escaping @Sendable (NetworkPathVerdict) -> Void
    ) -> RecoverySubscriptionToken {
        networkHandlers.append(handler)
        return RecoverySubscriptionToken { [weak self] in self?.networkCancellations += 1 }
    }

    func subscribe(_ handler: @escaping @Sendable () -> Void) -> RecoverySubscriptionToken {
        foregroundHandlers.append(handler)
        return RecoverySubscriptionToken { [weak self] in self?.foregroundCancellations += 1 }
    }
}
