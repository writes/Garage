import Foundation
@testable import Garage

@MainActor
final class CrashReporterSpy: CrashReporting {
    private(set) var enabledValues: [Bool] = []
    private(set) var recordedContexts: [String] = []

    func setEnabled(_ enabled: Bool) {
        enabledValues.append(enabled)
    }

    func record(_: Error, context: String) {
        recordedContexts.append(context)
    }
}
