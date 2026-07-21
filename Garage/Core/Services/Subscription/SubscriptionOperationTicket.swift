@MainActor
final class OperationTicket<Value: Sendable> {
    private var terminalValue: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []

    init() {}

    init(resolved value: Value) {
        terminalValue = value
    }

    func resolve(_ value: Value) {
        guard terminalValue == nil else {
            assertionFailure("OperationTicket resolved more than once")
            return
        }
        terminalValue = value
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume(returning: value) }
    }

    func awaitValue() async -> Value {
        if let terminalValue { return terminalValue }
        return await withCheckedContinuation { continuation in
            if let terminalValue {
                continuation.resume(returning: terminalValue)
            } else {
                waiters.append(continuation)
            }
        }
    }

#if DEBUG
    var isResolved: Bool { terminalValue != nil }
    var waiterCount: Int { waiters.count }
#endif
}
