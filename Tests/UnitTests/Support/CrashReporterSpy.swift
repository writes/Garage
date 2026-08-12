import Foundation
@testable import Garage

@MainActor
final class CrashReporterSpy: CrashReporting {
    private(set) var enabledValues: [Bool] = []
    private(set) var recordedContexts: [String] = []
    private(set) var breadcrumbs: [String] = []
    private(set) var experimentContexts: [(arm: ExperimentArm, epoch: Int)] = []

    func setEnabled(_ enabled: Bool) {
        enabledValues.append(enabled)
    }

    func setExperimentContext(arm: ExperimentArm, epoch: Int) {
        experimentContexts.append((arm, epoch))
    }

    func record(_: Error, context: String) {
        recordedContexts.append(context)
    }

    func breadcrumb(_ message: String) {
        breadcrumbs.append(message)
    }
}
