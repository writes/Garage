import Foundation

// MARK: - Receipt-capture prefill (parallel to +EditPrefill.swift's voice/edit seeding). Kept in
// its own file because EntryFormViewModel.swift already sits at the file cap.

extension EntryFormViewModel {
    /// Seeds the shared fields from a parsed receipt. Parallel to `applyVoicePrefill`: the user
    /// reviews every value before saving, so this only prefills — it never commits. Attachment
    /// staging is Pro-gated here (plan §5's cross-feature entitlement rule: a free teaser user
    /// gets the field prefill but not the staged original, plus an upsell hint the scaffold shows).
    func applyReceiptPrefill(_ package: ReceiptPrefillPackage, isPro: Bool) {
        let proposal = package.proposal
        wasReceiptSeeded = true
        receiptConfirmationToken = package.token
        receiptPrefillRawFields = Self.rawModelFields(from: proposal)
        receiptPrefillSeededFields = []
        receiptPrefillEffectiveSeed = nil
        if proposal.entryDate != nil {
            entryDate = proposal.resolvedDate(default: entryDate)
            receiptPrefillSeededFields.insert(.date)
        }
        if let odometer = proposal.odometerReading, odometer > 0 {
            odometerReading = String(odometer)
            receiptPrefillSeededFields.insert(.odometer)
        }
        if let receiptCost = proposal.cost, receiptCost > 0 {
            cost = Self.costString(receiptCost)
            receiptPrefillSeededFields.insert(.cost)
        }
        if let shop = proposal.shopName?.trimmed, !shop.isEmpty {
            shopName = shop
            isDiy = false
            receiptPrefillSeededFields.formUnion([.shop, .diy])
        } else if let receiptIsDiy = proposal.isDiy {
            isDiy = receiptIsDiy
            receiptPrefillSeededFields.insert(.diy)
        }
        if receiptPrefillRawFields.contains(.notes) {
            notes = Self.seededNotes(from: proposal)
            receiptPrefillSeededFields.insert(.notes)
        }
        stageReceiptAttachments(package.attachments, isPro: isPro)
    }

    /// Second pass over the receipt seed, run by EntryFormScaffold's `.task` once `prepare()` has
    /// loaded the odometer bounds — i.e. after every value the user is about to review is in place.
    ///
    /// This used to OVERWRITE the receipt's odometer with the validation floor whenever the receipt
    /// read lower, filing the printed number away in a note. That stored a mileage the vehicle
    /// never had on that date and skewed every miles-since-service figure MaintenanceAdvisor
    /// derives from it — the app inventing data about the user's car. It existed only because the
    /// floor was the vehicle's max-ever reading, which made backfilling an old receipt impossible.
    /// The floor is date-scoped now (`OdometerBounds`), so the receipt's true mileage validates on
    /// its own and is kept exactly as printed; the substitution and its note are gone.
    ///
    /// What remains is the baseline snapshot `trackReceiptFieldOutcomes` compares against to tell
    /// an edited field from an untouched one.
    func captureReceiptPrefillBaseline() {
        guard wasReceiptSeeded else { return }
        captureReceiptPrefillEffectiveSeed()
    }

    var unreadReceiptFieldsCaption: String? {
        guard wasReceiptSeeded else { return nil }
        let unread = ReceiptPrefillField.allCases.filter { !receiptPrefillRawFields.contains($0) }
        guard !unread.isEmpty else { return nil }
        return "Not read from the receipt: " + unread.map(\.caption).joined(separator: ", ")
    }

    /// Emits only field identifiers and edited booleans. Values remain in the local form and are
    /// never copied into analytics.
    func trackReceiptFieldOutcomes() {
        guard let seed = receiptPrefillEffectiveSeed else { return }
        for field in ReceiptPrefillField.allCases where receiptPrefillSeededFields.contains(field) {
            analytics.track(.receiptFieldOutcome(field: field, edited: seed.isEdited(field, in: self)))
        }
    }

    func clearReceiptPrefillTracking() {
        receiptPrefillRawFields = []
        receiptPrefillSeededFields = []
        receiptPrefillEffectiveSeed = nil
    }

    /// `lineItems` join into notes with a "• " bullet per line (plan §3's wire contract keeps
    /// them on the wire rather than folding them server-side, so the odometer-floor note above
    /// and this join both compose client-side, in one place).
    private static func seededNotes(from proposal: ReceiptEntryProposal) -> String {
        var parts: [String] = []
        if let receiptNotes = proposal.notes?.trimmed, !receiptNotes.isEmpty {
            parts.append(receiptNotes)
        }
        let bulletedItems = (proposal.lineItems ?? [])
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .map { "• \($0)" }
        if !bulletedItems.isEmpty {
            parts.append(bulletedItems.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func rawModelFields(from proposal: ReceiptEntryProposal) -> Set<ReceiptPrefillField> {
        var fields: Set<ReceiptPrefillField> = []
        if proposal.entryDate != nil { fields.insert(.date) }
        if proposal.odometerReading != nil { fields.insert(.odometer) }
        if proposal.cost != nil { fields.insert(.cost) }
        if proposal.shopName != nil { fields.insert(.shop) }
        if proposal.isDiy != nil { fields.insert(.diy) }
        if proposal.notes != nil || proposal.lineItems != nil { fields.insert(.notes) }
        return fields
    }

    private func captureReceiptPrefillEffectiveSeed() {
        receiptPrefillEffectiveSeed = ReceiptPrefillEffectiveSeed(
            date: receiptPrefillSeededFields.contains(.date) ? entryDate : nil,
            odometer: receiptPrefillSeededFields.contains(.odometer) ? odometerReading : nil,
            cost: receiptPrefillSeededFields.contains(.cost) ? cost : nil,
            shop: receiptPrefillSeededFields.contains(.shop) ? shopName : nil,
            diy: receiptPrefillSeededFields.contains(.diy) ? isDiy : nil,
            notes: receiptPrefillSeededFields.contains(.notes) ? notes : nil
        )
    }

    private func stageReceiptAttachments(_ attachments: [ReceiptPrefillAttachment], isPro: Bool) {
        guard !attachments.isEmpty else { return }
        guard isPro else {
            receiptAttachmentNeedsPro = true
            return
        }
        for attachment in attachments {
            switch attachment.kind {
            case .image: addPendingImage(attachment.data)
            case .pdf: addPendingPDF(attachment.data, filename: attachment.displayName)
            }
        }
    }
}

struct ReceiptPrefillEffectiveSeed: Equatable {
    let date: Date?
    let odometer: String?
    let cost: String?
    let shop: String?
    let diy: Bool?
    let notes: String?

    @MainActor
    func isEdited(_ field: ReceiptPrefillField, in form: EntryFormViewModel) -> Bool {
        switch field {
        case .date: return date.map { $0 != form.entryDate } ?? false
        case .odometer: return odometer.map { $0 != form.odometerReading } ?? false
        case .cost: return cost.map { $0 != form.cost } ?? false
        case .shop: return shop.map { $0 != form.shopName } ?? false
        case .diy: return diy.map { $0 != form.isDiy } ?? false
        case .notes: return notes.map { $0 != form.notes } ?? false
        }
    }
}
