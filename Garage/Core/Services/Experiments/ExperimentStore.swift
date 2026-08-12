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
        /// Server registry override (`experimentConfig` callable), cached so a kill switch
        /// fetched in one session still applies at the next cold launch even offline.
        var overrideDefinitions: [ExperimentDefinition]?

        init() {
            unitID = UUID().uuidString
            assignments = [:]
            overrideDefinitions = nil
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
    /// The BUNDLED registry compiled into this build.
    private let registry: ExperimentRegistry
    private let analytics: any AnalyticsTracking
    private let crashReporter: any CrashReporting
    /// Fires when a definition is refused. The production default traps in DEBUG and is a
    /// no-op in release — a bad server override must be impossible to miss on a debug build
    /// and impossible to crash on in the field. Tests substitute a recorder because the
    /// refusal paths are exactly what they assert.
    private let onPolicyViolation: (String) -> Void
    private var state: State

    init(
        defaults: UserDefaults?,
        registry: ExperimentRegistry,
        analytics: any AnalyticsTracking,
        crashReporter: any CrashReporting = CrashReporter.shared,
        onPolicyViolation: @escaping (String) -> Void = { assertionFailure($0) }
    ) {
        self.defaults = defaults
        self.registry = registry
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.onPolicyViolation = onPolicyViolation
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
            persist()
        }
    }

    /// The definition this session must obey: the bundled definition, replaced by a cached
    /// server override only when the override passes the allocation clamp, and forced to
    /// KILLED when the surviving roster allocates an arm this build cannot render. Override
    /// resolution is definition-granular so a server doc naming one experiment leaves every
    /// other bundled experiment untouched.
    private func effectiveDefinition(for id: ExperimentID) -> ExperimentDefinition? {
        guard let bundled = registry.definition(for: id) else { return nil }
        var definition = bundled
        if let override = state.overrideDefinitions?.first(where: { $0.id == id }) {
            if let rejection = ExperimentPolicy.rejection(of: override, against: bundled) {
                onPolicyViolation("experiment override \(id.rawValue) refused: \(rejection.rawValue)")
            } else {
                definition = override
            }
        }
        let unrenderable = ExperimentPolicy.unrenderableArms(in: definition)
        guard unrenderable.isEmpty else {
            let arms = unrenderable.map(\.rawValue).joined(separator: ",")
            onPolicyViolation("experiment \(id.rawValue) killed: build cannot render \(arms)")
            return definition.killed()
        }
        return definition
    }

    /// The definition + arm this session actually renders, or nil when the experiment is
    /// suppressed (absent, killed, clamped away, or holding an arm this build cannot render).
    /// Suppressed means control renders and NOTHING is emitted: an exposure labelling an arm
    /// the user never saw corrupts the analysis more quietly than a missing one.
    private func liveAssignment(for id: ExperimentID) -> (definition: ExperimentDefinition, arm: ExperimentArm)? {
        guard let definition = effectiveDefinition(for: id), !definition.isKilled else { return nil }
        let resolved = lockedArm(for: id, definition: definition)
        // A sticky assignment written by an earlier build can name an arm this one dropped;
        // the roster check above cannot see it.
        guard ExperimentPolicy.canRender(resolved, for: id) else {
            onPolicyViolation("experiment \(id.rawValue) suppressed: stored arm \(resolved.rawValue) is unrenderable")
            return nil
        }
        return (definition, resolved)
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
        return liveAssignment(for: id)?.arm ?? .control
    }

    private func lockedArm(for id: ExperimentID, definition: ExperimentDefinition) -> ExperimentArm {
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
        guard let (definition, arm) = liveAssignment(for: id) else { return }
        guard var assignment = state.assignments[id.rawValue] else { return }

        // Properties are idempotent STATE and re-emit on every call: an identity discarded
        // before consent (sign-out pre-consent, profile mismatch) drops the held values, and
        // without this re-emission the next consenting identity would permanently lack
        // `design_arm` (Gemini cross-check #2). The EVENT below stays once-per-epoch.
        analytics.setUserProperty(.designArm(arm))
        analytics.setUserProperty(.experimentEpoch(definition.epoch))
        analytics.setUserProperty(.notifHoldout(isInNotificationHoldout))
        // Same arm/epoch onto the crash keys: the 99.5% per-arm crash-free guardrail cannot be
        // read without them. The facade holds them until consent enables collection.
        crashReporter.setExperimentContext(arm: arm, epoch: definition.epoch)

        guard !assignment.exposedEpochs.contains(definition.epoch) else { return }
        assignment.exposedEpochs.append(definition.epoch)
        state.assignments[id.rawValue] = assignment
        persist()
        analytics.track(.experimentExposure(experiment: id, arm: arm, epoch: definition.epoch))
    }

    /// Whether the design survey should be offered: exposed to an active experiment this epoch
    /// and not yet submitted for it.
    func isSurveyAvailable(for id: ExperimentID) -> Bool {
        // liveAssignment, not effectiveDefinition: a sticky assignment this build suppresses
        // (P0.1) renders control and records nothing, so it must not be surveyed as an
        // experiment participant either (cross-check finding).
        guard let (definition, _) = liveAssignment(for: id) else { return false }
        guard let assignment = state.assignments[id.rawValue] else { return false }
        return assignment.exposedEpochs.contains(definition.epoch)
            && !assignment.surveySubmittedEpochs.contains(definition.epoch)
    }

    func markSurveySubmitted(for id: ExperimentID) {
        guard let (definition, _) = liveAssignment(for: id) else { return }
        guard var assignment = state.assignments[id.rawValue] else { return }
        guard !assignment.surveySubmittedEpochs.contains(definition.epoch) else { return }
        assignment.surveySubmittedEpochs.append(definition.epoch)
        state.assignments[id.rawValue] = assignment
        persist()
    }

    /// Applies a fetched server override: persists it (so it survives cold launches
    /// offline) and returns whether any experiment's EFFECTIVE state changed — the caller
    /// reapplies the design pack so an emergency kill restyles mid-session without a
    /// relaunch.
    @discardableResult
    func applyServerOverride(_ definitions: [ExperimentDefinition]) -> Bool {
        let before = state.overrideDefinitions
        guard before != definitions else { return false }
        state.overrideDefinitions = definitions
        persist()
        return true
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
