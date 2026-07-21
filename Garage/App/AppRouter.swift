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

    /// Carries a voice proposal from the capture sheet to the entry form it opens. Consumed once
    /// by the form that appears next, so a manually-opened form never picks up a stale prefill.
    private(set) var pendingVoicePrefill: VoiceEntryProposal?

    func present(_ sheet: Sheet) {
        activeSheet = sheet
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
}
