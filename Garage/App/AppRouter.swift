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

    /// Carries a voice proposal from the capture sheet to the entry form it opens. Consumed once
    /// by the form that appears next, so a manually-opened form never picks up a stale prefill.
    private(set) var pendingVoicePrefill: VoiceEntryProposal?

    /// Same one-shot pattern as pendingVoicePrefill, kept separate (plan §2): a receipt scan and
    /// a voice dictation are independent AI sources and must never be conflated into one slot.
    private(set) var pendingReceiptPrefill: ReceiptPrefillPackage?

    /// Carries an existing entry from EntryDetailView to the edit form it opens. Same one-shot
    /// pattern as pendingVoicePrefill: consumed once by the form that appears next.
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
        let isGatedSheet: Bool
        switch sheet {
        case .entryPicker, .voiceQuickAdd, .receiptCapture, .entryForm:
            isGatedSheet = true
        case .vehicleForm, .export, .subscription, .designSurvey:
            isGatedSheet = false
        }

        guard isGatedSheet, !hasVehicles() else {
            activeSheet = sheet
            reportOpened(sheet)
            return
        }
        pendingVoicePrefill = nil
        pendingReceiptPrefill = nil
        pendingEditEntry = nil
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
        case .subscription, .designSurvey: return
        }
        analytics.track(.formOpened(form: form))
    }

    func dismissSheet() {
        activeSheet = nil
    }

    /// Swap the voice sheet for the proposed entry form, seeding it with the spoken details.
    func presentVoicePrefilledForm(_ proposal: VoiceEntryProposal) {
        pendingVoicePrefill = proposal
        present(.entryForm(proposal.entryType))
    }

    func consumeVoicePrefill() -> VoiceEntryProposal? {
        defer { pendingVoicePrefill = nil }
        return pendingVoicePrefill
    }

    /// Swap the receipt sheet for the proposed entry form, seeding it with the parsed receipt.
    func presentReceiptPrefilledForm(_ package: ReceiptPrefillPackage) {
        pendingReceiptPrefill = package
        present(.entryForm(package.proposal.entryType))
    }

    func consumeReceiptPrefill() -> ReceiptPrefillPackage? {
        defer { pendingReceiptPrefill = nil }
        return pendingReceiptPrefill
    }

    /// Opens the edit form for an existing entry, seeding it via the same one-shot handoff as
    /// voice prefill. Goes through `present` (not a raw `activeSheet` assignment) so the
    /// zero-vehicle gate still applies to it like every other entry-form presentation.
    func presentEditForm(for entry: FirestoreEntry) {
        pendingEditEntry = entry
        present(.entryForm(entry.entryType))
    }

    func consumeEditEntry() -> FirestoreEntry? {
        defer { pendingEditEntry = nil }
        return pendingEditEntry
    }
}
