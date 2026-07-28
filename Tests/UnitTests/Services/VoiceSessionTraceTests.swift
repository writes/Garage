import Foundation
import Testing
@testable import Garage

@MainActor
struct VoiceSessionTraceTests {
    private func makeTrace() -> (VoiceSessionTrace, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-trace-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (VoiceSessionTrace(directory: dir), dir.appendingPathComponent("voice-session-trace.txt"))
    }

    @Test func markPersistsStagesAndEndCleanlyRemovesThem() throws {
        let (trace, file) = makeTrace()

        trace.mark("vm.permission")
        trace.mark("tap.install sr=48000 ch=1")

        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents == "vm.permission\ntap.install sr=48000 ch=1")

        trace.endCleanly()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func abandonedTraceIsReportedOnceWithLastStageContext() {
        let (trace, file) = makeTrace()
        trace.mark("vm.permission")
        trace.mark("engine.start")
        let reporter = CrashReporterSpy()

        trace.reportAbandonedTrace(to: reporter)

        #expect(reporter.recordedContexts == ["voice-died-at-engine.start"])
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // Once per launch: a second call must not re-report even if a new file appears.
        trace.mark("vm.permission")
        trace.reportAbandonedTrace(to: reporter)
        #expect(reporter.recordedContexts.count == 1)
    }

    @Test func cleanShutdownReportsNothing() {
        let (trace, _) = makeTrace()
        trace.mark("vm.permission")
        trace.endCleanly()
        let reporter = CrashReporterSpy()

        trace.reportAbandonedTrace(to: reporter)

        #expect(reporter.recordedContexts.isEmpty)
    }
}
