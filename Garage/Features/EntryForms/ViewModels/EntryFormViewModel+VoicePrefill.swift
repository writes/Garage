import Foundation

// Voice shared-field seeding is kept beside receipt prefill extensions rather than in the core
// view model, which remains focused on state ownership and the save transaction.

extension EntryFormViewModel {
    /// Seeds the shared fields from a voice proposal. The user reviews every value before saving,
    /// so this only prefills — it never commits. Type-specific details are left for the form.
    func applyVoicePrefill(_ proposal: VoiceEntryProposal) {
        wasVoiceSeeded = true
        entryDate = proposal.resolvedDate(default: entryDate)
        if let odometer = proposal.odometerReading, odometer > 0 {
            odometerReading = String(odometer)
        }
        if let spokenCost = proposal.cost, spokenCost > 0 {
            cost = Self.costString(spokenCost)
        }
        if let shop = proposal.shopName?.trimmed, !shop.isEmpty {
            shopName = shop
            isDiy = false
        } else if let spokenIsDiy = proposal.isDiy {
            isDiy = spokenIsDiy
        }
        if let spokenNotes = proposal.notes?.trimmed, !spokenNotes.isEmpty {
            notes = spokenNotes
        }
    }
}
