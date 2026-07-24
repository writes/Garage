import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    enum Sheet: Identifiable, Equatable {
        case entryPicker
        case voiceQuickAdd
        case entryForm(EntryType)
        case vehicleForm
        case export
        case subscription(PaywallSource)

        var id: String {
            switch self {
            case .entryPicker: return "entryPicker"
            case .voiceQuickAdd: return "voiceQuickAdd"
            case .entryForm(let type): return "entryForm-\(type.rawValue)"
            case .vehicleForm: return "vehicleForm"
            case .export: return "export"
            case .subscription(let source): return "subscription-\(source.rawValue)"
            }
        }
    }

    var activeSheet: Sheet?

    /// Injected from the app root (GarageApp), where AppState already exists. A closure, not a
    /// stored AppState reference, so AppRouter stays constructible/testable without pulling in
    /// the whole app-state graph. Defaults to `true` so call sites that don't care about the
    /// zero-vehicle gate (previews, non-gated tests) keep today's behavior.
    private let hasVehicles: () -> Bool

    /// Carries a voice proposal from the capture sheet to the entry form it opens. Consumed once
    /// by the form that appears next, so a manually-opened form never picks up a stale prefill.
    private(set) var pendingVoicePrefill: VoiceEntryProposal?

    /// Carries an existing entry from EntryDetailView to the edit form it opens. Same one-shot
    /// pattern as pendingVoicePrefill: consumed once by the form that appears next.
    private(set) var pendingEditEntry: FirestoreEntry?

    init(hasVehicles: @escaping () -> Bool = { true }) {
        self.hasVehicles = hasVehicles
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
        case .entryPicker, .voiceQuickAdd, .entryForm:
            isGatedSheet = true
        case .vehicleForm, .export, .subscription:
            isGatedSheet = false
        }

        guard isGatedSheet, !hasVehicles() else {
            activeSheet = sheet
            return
        }
        pendingVoicePrefill = nil
        pendingEditEntry = nil
        activeSheet = .vehicleForm
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
