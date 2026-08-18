import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    enum Sheet: Identifiable, Equatable {
        case entryPicker
        case voiceQuickAdd
        case receiptCapture
        case entryForm(EntryType)
        case vehicleForm
        case export
        case subscription(PaywallSource)
        case designSurvey
        /// The Underhood arm's §2.3 settings accessory. Routed through the router — not a local
        /// `.sheet` at the accessory — because SettingsView's own actions present ROUTER sheets
        /// (export, paywall): with Settings presented by a child host, those root-hosted sheets
        /// cannot present over it and the flows dead-end. One host means a follow-on `present`
        /// replaces the Settings sheet instead. Control never routes here (it has a Settings tab).
        case settings

        var id: String {
            switch self {
            case .entryPicker: return "entryPicker"
            case .voiceQuickAdd: return "voiceQuickAdd"
            case .receiptCapture: return "receiptCapture"
            case .entryForm(let type): return "entryForm-\(type.rawValue)"
            case .vehicleForm: return "vehicleForm"
            case .export: return "export"
            case .subscription(let source): return "subscription-\(source.rawValue)"
            case .designSurvey: return "designSurvey"
            case .settings: return "settings"
            }
        }
    }

    var activeSheet: Sheet?

    /// Injected from the app root (GarageApp), where AppState already exists. A closure, not a
    /// stored AppState reference, so AppRouter stays constructible/testable without pulling in
    /// the whole app-state graph. Defaults to `true` so call sites that don't care about the
    /// zero-vehicle gate (previews, non-gated tests) keep today's behavior.
    private let hasVehicles: () -> Bool

    /// Injected rather than reached through AppState, so AppRouter stays constructible in
    /// previews and tests without the whole app-state graph — same reasoning as `hasVehicles`.
    private let analytics: any AnalyticsTracking

    /// Carries a voice proposal from the capture sheet to the entry form it opens. Held (not
    /// consumed) for the lifetime of that presentation: SwiftUI may build a sheet's content more
    /// than once during the voice→form swap, and a consume-on-first-build handoff hands the
    /// payload to a throwaway build while the surviving build renders blank. Every OTHER
    /// presentation path clears it (see `present`), so a manually-opened form never picks up a
    /// stale prefill.
    private(set) var pendingVoicePrefill: VoiceEntryProposal?

    /// Same held-slot pattern as pendingVoicePrefill, kept separate (plan §2): a receipt scan and
    /// a voice dictation are independent AI sources and must never be conflated into one slot.
    private(set) var pendingReceiptPrefill: ReceiptPrefillPackage?

    /// Carries an existing entry from EntryDetailView to the edit form it opens. Same held-slot
    /// pattern as pendingVoicePrefill.
    private(set) var pendingEditEntry: FirestoreEntry?

    init(
        hasVehicles: @escaping () -> Bool = { true },
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.hasVehicles = hasVehicles
        self.analytics = analytics
    }

    /// Audit finding (zero-vehicle activation dead end): a fresh account has no vehicles, so
    /// opening the entry picker, voice capture, or an entry form leads straight to a save that
    /// silently no-ops (EntryFormScaffold.saveIfAdmitted -> appState.currentVehicle == nil).
    /// Redirect those three sheets to vehicle creation instead so first use always has a path
    /// forward. Also drops any pending one-shot prefill/edit so a later real entry-form
    /// presentation never consumes stale state from the redirected attempt.
    ///
    /// Deliberately split pattern-matching from the guard (not `case .a, .b, .c where cond:`) —
    /// review caught that Swift's `where` after a comma-list only binds to the LAST pattern, so
    /// the three-case-with-trailing-where form silently gated only `.entryForm` and let
    /// `.entryPicker`/`.voiceQuickAdd` through unconditionally, even with vehicles present.
    func present(_ sheet: Sheet) {
        // Any plain presentation starts a NEW flow, so whatever a previous voice/receipt/edit
        // handoff left behind is stale by definition. The three presentXxx handoff entry points
        // below bypass this wipe via presentPreservingHandoff — they set their slot first.
        clearPendingHandoffs()
        presentPreservingHandoff(sheet)
    }

    private func clearPendingHandoffs() {
        pendingVoicePrefill = nil
        pendingReceiptPrefill = nil
        pendingEditEntry = nil
    }

    private func presentPreservingHandoff(_ sheet: Sheet) {
        let isGatedSheet: Bool
        switch sheet {
        case .entryPicker, .voiceQuickAdd, .receiptCapture, .entryForm:
            isGatedSheet = true
        case .vehicleForm, .export, .subscription, .designSurvey, .settings:
            isGatedSheet = false
        }

        guard isGatedSheet, !hasVehicles() else {
            activeSheet = sheet
            reportOpened(sheet)
            return
        }
        clearPendingHandoffs()
        activeSheet = .vehicleForm
        // Report the redirect target, not the request: attributing this open to `entry` would
        // misreport the funnel, since what the user is actually looking at is vehicle creation.
        reportOpened(.vehicleForm)
    }

    /// The paywall is excluded because it already reports `paywall_viewed` from its own
    /// `onAppear`; the survey likewise fires its own `survey_submitted`/`survey_dismissed`
    /// pair — emitting `form_opened` for either would double-count one impression.
    private func reportOpened(_ sheet: Sheet) {
        let form: FormKind
        switch sheet {
        case .vehicleForm: form = .vehicle
        case .entryPicker: form = .entryPicker
        case .entryForm: form = .entry
        case .voiceQuickAdd: form = .voiceQuickAdd
        case .receiptCapture: form = .receiptCapture
        case .export: form = .export
        case .subscription, .designSurvey, .settings: return
        }
        analytics.track(.formOpened(form: form))
    }

    /// Programmatic close (the save path). Interactive swipe-down instead writes nil straight
    /// through ContentView's sheet binding, deliberately WITHOUT clearing the handoff slots:
    /// SwiftUI can emit transient nil writes while it swaps one sheet for another, and clearing
    /// there would drop an in-flight prefill. Stale slots are harmless — every next `present`
    /// wipes them before any form could read them.
    func dismissSheet() {
        clearPendingHandoffs()
        activeSheet = nil
    }

    /// Swap the voice sheet for the proposed entry form, seeding it with the spoken details.
    func presentVoicePrefilledForm(_ proposal: VoiceEntryProposal) {
        clearPendingHandoffs()
        pendingVoicePrefill = proposal
        presentPreservingHandoff(.entryForm(proposal.entryType))
    }

    /// Swap the receipt sheet for the proposed entry form, seeding it with the parsed receipt.
    func presentReceiptPrefilledForm(_ package: ReceiptPrefillPackage) {
        clearPendingHandoffs()
        pendingReceiptPrefill = package
        presentPreservingHandoff(.entryForm(package.proposal.entryType))
    }

    /// Opens the edit form for an existing entry, seeding it via the same held-slot handoff as
    /// voice prefill. Goes through the gate-checked path so the zero-vehicle redirect still
    /// applies to it like every other entry-form presentation.
    func presentEditForm(for entry: FirestoreEntry) {
        clearPendingHandoffs()
        pendingEditEntry = entry
        presentPreservingHandoff(.entryForm(entry.entryType))
    }
}
