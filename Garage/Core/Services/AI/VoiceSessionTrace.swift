import Foundation

/// Crash forensics for the voice path. The outstanding voice crash is an uncatchable
/// Objective-C exception — no Swift `catch` sees it, and the tester's report says only
/// "it crashed". Each stage is written SYNCHRONOUSLY to a small file before the next
/// AVFoundation call, so when the process dies the file names the last stage reached.
/// A cleanly ended session deletes the file; a file still present at the next launch is
/// therefore evidence the app died (or was force-killed) mid-voice.
///
/// Stages are short static labels ("tap.installed"), never user content or transcripts.
@MainActor
final class VoiceSessionTrace {
    static let shared = VoiceSessionTrace()

    private var stages: [String] = []
    private var hasReportedThisLaunch = false
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) {
        fileURL = directory.appendingPathComponent("voice-session-trace.txt")
    }

    func mark(_ stage: String) {
        stages.append(stage)
        // Atomic whole-file rewrite: the trace is tiny, and unlike a UserDefaults write this
        // is on disk before the call on the next line can crash the process.
        try? stages.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        CrashReporter.shared.breadcrumb("voice \(stage)")
    }

    /// Every non-crashing exit of the voice flow lands here — success, shown failure, cancel,
    /// or interruption. Only a dead process leaves the file behind.
    func endCleanly() {
        stages = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Call after consent is applied. A leftover trace is reported as a non-fatal whose context
    /// carries the last stage, so the console names the failing call site even though the crash
    /// itself was an uncatchable exception that Crashlytics attributes to the ObjC runtime.
    func reportAbandonedTrace(to reporter: any CrashReporting) {
        guard !hasReportedThisLaunch else { return }
        hasReportedThisLaunch = true
        guard let trace = try? String(contentsOf: fileURL, encoding: .utf8), !trace.isEmpty else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
        let lastStage = trace.split(separator: "\n").last.map(String.init) ?? "unknown"
        AppLogger.shared.error("Previous voice session did not end cleanly; last stage: \(lastStage)")
        reporter.record(VoiceSessionAbandoned(lastStage: lastStage, trace: trace),
                        context: "voice-died-at-\(lastStage)")
    }
}

/// The non-fatal recorded when a launch finds an abandoned voice trace. `CustomNSError` so the
/// full stage list rides along in the report's userInfo instead of just the type name.
struct VoiceSessionAbandoned: Error, CustomNSError {
    let lastStage: String
    let trace: String

    static var errorDomain: String { "VoiceSessionAbandoned" }
    var errorCode: Int { 1 }
    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "voice session died at \(lastStage)", "trace": trace]
    }
}
