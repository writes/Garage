import Foundation
import Observation

/// Device-local experiment state: the stable unit identity, sticky arm assignments, and
/// exposure/survey bookkeeping. Persistence follows the ReviewPromptStore pattern — one
/// versioned JSON blob in UserDefaults, `nil` defaults = fully in-memory (tests, demo,
/// UI-test), corrupt data discarded rather than migrated.
///
/// IDENTITY. The unit is a persisted install-scoped UUID, not the Firebase uid: the design
/// arm must be selected before the first frame (LoginView is inside the experiment), and the
/// uid does not exist until Firebase's async auth listener fires. The arm LOCKS at first
/// resolution and never re-hashes on sign-in/sign-out — a mid-session design switch would
/// destroy within-user consistency, the exact property the sticky policy exists for.
/// Analytics still joins per-uid: the exposure event and `design_arm` user property flow
/// through the consent gate and land attributed to whichever uid consents.
@MainActor
@Observable
final class ExperimentStore {
    private struct Assignment: Codable, Equatable {
        var arm: ExperimentArm
        var epoch: Int
        /// Epochs whose exposure event has been emitted — exposure fires once per epoch so a
        /// roster change re-exposes (fresh analysis cohort) without double-counting within one.
        var exposedEpochs: [Int]
        var surveySubmittedEpochs: [Int]
    }

    private struct State: Codable, Equatable {
        var unitID: String
        var assignments: [String: Assignment]

        init() {
            unitID = UUID().uuidString
            assignments = [:]
        }
    }

    private static let storageKey = "garage.experiments.v1"
    /// Launch-argument arm override for UI journeys and manual QA of a variant
    /// (e.g. `EXPERIMENT_FORCE_DESIGN_ARM=variant_a`). Read only in DEBUG builds.
    private static let forceArmKey = "EXPERIMENT_FORCE_DESIGN_ARM"

    static let shared = ExperimentStore(
        defaults: AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode ? nil : .standard,
        registry: .bundled,
        analytics: AnalyticsService.shared
    )

    private let defaults: UserDefaults?
    private let registry: ExperimentRegistry
    private let analytics: any AnalyticsTracking
    private var state: State

    init(defaults: UserDefaults?, registry: ExperimentRegistry, analytics: any AnalyticsTracking) {
        self.defaults = defaults
        self.registry = registry
        self.analytics = analytics
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
            persist()
        }
    }

    var unitID: String { state.unitID }

    var isInNotificationHoldout: Bool {
        ExperimentAssigner.isInNotificationHoldout(unitID: state.unitID)
    }

    /// The locked arm for an experiment, resolving (and locking) it on first read.
    /// Kill switch forces `.control` WITHOUT touching the stored assignment, so lifting it
    /// restores the user's arm. Epoch semantics: a surviving arm carries into the new epoch;
    /// a retired arm re-hashes on the new epoch.
    func arm(for id: ExperimentID) -> ExperimentArm {
#if DEBUG
        if id == .designMegatest,
           let forced = ProcessInfo.processInfo.environment[Self.forceArmKey],
           let forcedArm = ExperimentArm(rawValue: forced) {
            return forcedArm
        }
#endif
        guard let definition = registry.definition(for: id) else { return .control }
        if definition.isKilled { return .control }

        if var existing = state.assignments[id.rawValue] {
            if existing.epoch != definition.epoch {
                if !definition.activeArms.contains(existing.arm) {
                    existing.arm = ExperimentAssigner.arm(unitID: state.unitID, definition: definition)
                }
                existing.epoch = definition.epoch
                state.assignments[id.rawValue] = existing
                persist()
            }
            return existing.arm
        }

        let assigned = ExperimentAssigner.arm(unitID: state.unitID, definition: definition)
        state.assignments[id.rawValue] = Assignment(
            arm: assigned,
            epoch: definition.epoch,
            exposedEpochs: [],
            surveySubmittedEpochs: []
        )
        persist()
        return assigned
    }

    /// Emits the exposure event + user properties, once per (experiment, epoch). Call from the
    /// first eligible render — exposure, not assignment, defines the analysis population. All
    /// emission goes through `analytics.track`/`setUserProperty`, so the consent gate buffers
    /// pre-consent exactly like the sign-in funnel.
    func recordExposureIfNeeded(for id: ExperimentID) {
        let arm = arm(for: id)
        guard let definition = registry.definition(for: id), !definition.isKilled else { return }
        guard var assignment = state.assignments[id.rawValue] else { return }

        // Properties are idempotent STATE and re-emit on every call: an identity discarded
        // before consent (sign-out pre-consent, profile mismatch) drops the held values, and
        // without this re-emission the next consenting identity would permanently lack
        // `design_arm` (Gemini cross-check #2). The EVENT below stays once-per-epoch.
        analytics.setUserProperty(.designArm(arm))
        analytics.setUserProperty(.experimentEpoch(definition.epoch))
        analytics.setUserProperty(.notifHoldout(isInNotificationHoldout))

        guard !assignment.exposedEpochs.contains(definition.epoch) else { return }
        assignment.exposedEpochs.append(definition.epoch)
        state.assignments[id.rawValue] = assignment
        persist()
        analytics.track(.experimentExposure(experiment: id, arm: arm, epoch: definition.epoch))
    }

    /// Whether the design survey should be offered: exposed to an active experiment this epoch
    /// and not yet submitted for it.
    func isSurveyAvailable(for id: ExperimentID) -> Bool {
        guard let definition = registry.definition(for: id), !definition.isKilled else { return false }
        guard let assignment = state.assignments[id.rawValue] else { return false }
        return assignment.exposedEpochs.contains(definition.epoch)
            && !assignment.surveySubmittedEpochs.contains(definition.epoch)
    }

    func markSurveySubmitted(for id: ExperimentID) {
        guard let definition = registry.definition(for: id) else { return }
        guard var assignment = state.assignments[id.rawValue] else { return }
        guard !assignment.surveySubmittedEpochs.contains(definition.epoch) else { return }
        assignment.surveySubmittedEpochs.append(definition.epoch)
        state.assignments[id.rawValue] = assignment
        persist()
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
