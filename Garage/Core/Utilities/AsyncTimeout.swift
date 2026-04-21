import Foundation

enum AsyncTimeout {
    static func run<Result: Sendable, Failure: Error & Sendable>(
        nanoseconds: UInt64,
        timeoutError: @autoclosure @escaping @Sendable () -> Failure,
        operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        let operationTask = Task {
            try await operation()
        }

        defer {
            operationTask.cancel()
        }

        return try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask {
                try await operationTask.value
            }

            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw timeoutError()
            }

            guard let result = try await group.next() else {
                throw timeoutError()
            }

            group.cancelAll()
            operationTask.cancel()
            return result
        }
    }
}
