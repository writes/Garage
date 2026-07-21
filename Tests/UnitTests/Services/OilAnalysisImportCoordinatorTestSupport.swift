import Foundation
import Testing
@testable import Garage

@MainActor
final class SuspendedOilAnalysisCaller: OilAnalysisCalling {
    private var continuation: CheckedContinuation<CallerCompletion, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    func parseOilAnalysis(pdfBase64 _: String, now _: Date) async throws -> OilAnalysisEntry {
        callCount += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        let completion = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        switch completion {
        case .success(let entry): return entry
        case .failure(let error): throw error
        case .genericFailure: throw NSError(domain: "OilAnalysisImportTests", code: 1)
        }
    }

    func waitForCall(count expectedCount: Int = 1) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func complete(with completion: CallerCompletion) {
        continuation?.resume(returning: completion)
        continuation = nil
    }
}

enum CallerCompletion {
    case success(OilAnalysisEntry)
    case failure(OilAnalysisCallableError)
    case genericFailure
}

@MainActor
final class ScriptedPreflighter: OilAnalysisPDFPreflighting {
    enum Step: Sendable {
        case success(String)
        case failure(OilAnalysisPDFPreflightError)
        case suspended
    }

    private var steps: [Step]
    private var continuation: CheckedContinuation<Step, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func preflight(url _: URL) async throws -> String {
        callCount += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        let step = steps.removeFirst()
        switch step {
        case .success(let value): return value
        case .failure(let error): throw error
        case .suspended:
            let completion = await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            switch completion {
            case .success(let value): return value
            case .failure(let error): throw error
            case .suspended: preconditionFailure("Suspended preflight cannot complete with another suspension.")
            }
        }
    }

    func waitForCall(count expectedCount: Int = 1) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func completeSuspended(with step: Step) {
        continuation?.resume(returning: step)
        continuation = nil
    }
}

@MainActor
final class RecordingOilAnalysisSecurityScope: OilAnalysisPDFSecurityScopeAccessing {
    enum Event: Equatable {
        case acquired
        case released
    }

    var shouldAcquire = true
    private(set) var events: [Event] = []

    func acquire(for _: URL) -> Bool {
        events.append(.acquired)
        return shouldAcquire
    }

    func release(for _: URL) {
        events.append(.released)
    }
}

@MainActor
final class RecordingOilAnalysisDraftSink: OilAnalysisPrefillApplying {
    enum Event: Equatable {
        case began(UUID)
        case committed(UUID)
        case aborted(UUID)
    }

    private(set) var fields = OilAnalysisEditableFields()
    private(set) var events: [Event] = []
    private(set) var authorizedOwner: UUID?

    func beginAuthorizedImport(ownerID: UUID) {
        guard authorizedOwner == nil else { return }
        authorizedOwner = ownerID
        events.append(.began(ownerID))
    }

    func commitImportedPrefill(_ prefill: OilAnalysisImportPrefill, ownerID: UUID) {
        guard authorizedOwner == ownerID else { return }
        fields.apply(prefill)
        authorizedOwner = nil
        events.append(.committed(ownerID))
    }

    func abortAuthorizedImport(ownerID: UUID) {
        guard authorizedOwner == ownerID else { return }
        authorizedOwner = nil
        events.append(.aborted(ownerID))
    }
}

@MainActor
enum OilAnalysisImportTestSupport {
    static let sampleURL = URL(fileURLWithPath: "/tmp/oil-analysis.pdf")

    static func enabledAnalytics() -> AnalyticsSpy {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        return analytics
    }

    static func makeCoordinator(
        draftSink: (any OilAnalysisPrefillApplying)? = nil,
        preflighter: any OilAnalysisPDFPreflighting,
        caller: any OilAnalysisCalling,
        analytics: any AnalyticsTracking,
        securityScope: any OilAnalysisPDFSecurityScopeAccessing = RecordingOilAnalysisSecurityScope(),
        watchdogDelay: Duration = .seconds(30)
    ) -> OilAnalysisImportCoordinator {
        OilAnalysisImportCoordinator(
            preflighter: preflighter,
            caller: caller,
            now: { Date(timeIntervalSince1970: 1_783_944_000) },
            analytics: analytics,
            securityScope: securityScope,
            draftSink: draftSink,
            cancellationWatchdogDelay: watchdogDelay
        )
    }

    static func stage(
        _ coordinator: OilAnalysisImportCoordinator,
        url: URL = sampleURL,
        isSaveInProgress: Bool = false
    ) -> UUID {
        guard let sessionID = coordinator.beginPicker(saveInProgress: isSaveInProgress) else {
            Issue.record("Expected the idle coordinator to admit the picker.")
            return UUID()
        }
        coordinator.completePicker(
            sessionID: sessionID,
            result: .success(url),
            saveInProgress: isSaveInProgress
        )
        guard let requestID = coordinator.pendingConsent?.id else {
            Issue.record("Expected a staged PDF to require consent.")
            return UUID()
        }
        return requestID
    }

    static func confirm(
        _ coordinator: OilAnalysisImportCoordinator,
        requestID: UUID,
        clientIsPro: Bool = false,
        isSaveInProgress: Bool = false
    ) {
        _ = coordinator.confirmConsent(
            requestID: requestID,
            clientIsPro: clientIsPro,
            saveInProgress: isSaveInProgress
        )
    }

    static func waitForCompletion(_ coordinator: OilAnalysisImportCoordinator) async {
        for _ in 0 ..< 100 {
            if !coordinator.isImporting { return }
            await Task.yield()
        }
        #expect(!coordinator.isImporting)
    }

    static func sampleEntry(
        viscosity: String? = nil,
        milesOnOil: Int? = nil,
        iron: Double? = nil,
        aluminum: Double? = nil,
        recommendation: String? = nil
    ) -> OilAnalysisEntry {
        OilAnalysisEntry(
            labName: "L",
            pdfPath: nil,
            aluminum: aluminum,
            chromium: nil,
            iron: iron,
            copper: nil,
            lead: nil,
            tin: nil,
            molybdenum: nil,
            nickel: nil,
            manganese: nil,
            silver: nil,
            titanium: nil,
            silicon: nil,
            sodium: nil,
            potassium: nil,
            viscosity: viscosity,
            insolubles: nil,
            milesOnOil: milesOnOil,
            labRecommendation: recommendation
        )
    }
}
