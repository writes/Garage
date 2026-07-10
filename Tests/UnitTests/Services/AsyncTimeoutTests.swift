import Foundation
import Testing
@testable import Garage

struct AsyncTimeoutTests {
    @Test func run_returnsResultWhenOperationFinishesInTime() async throws {
        let value = try await AsyncTimeout.run(
            nanoseconds: 100_000_000,
            timeoutError: TimeoutTestError.timedOut
        ) {
            try await Task.sleep(nanoseconds: 10_000_000)
            return 42
        }

        #expect(value == 42)
    }

    @Test func run_throwsTimeoutWhenOperationStalls() async {
        do {
            _ = try await AsyncTimeout.run(
                nanoseconds: 10_000_000,
                timeoutError: TimeoutTestError.timedOut
            ) {
                try await Task.sleep(nanoseconds: 100_000_000)
                return 42
            }

            Issue.record("Expected AsyncTimeout to throw")
        } catch {
            #expect(error as? TimeoutTestError == .timedOut)
        }
    }
}

private enum TimeoutTestError: Error, Equatable, Sendable {
    case timedOut
}
