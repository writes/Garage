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

    /// Odometer-floor reconciliation (plan §2). `prepare()` loads `odometerFloor` AFTER
    /// `applyReceiptPrefill` above has already seeded `odometerReading`, so EntryFormScaffold's
    /// `.task` runs this as a SECOND pass once the floor is known. The flagship use case is
    /// backfilling an OLD receipt whose mileage sits below the vehicle's current reading — left
    /// alone, that value hard-blocks Save via `Validators.odometer`.
    ///
    /// Deviation from the plan's literal "clear the odometer field": `Validators.odometer` (via
    /// `positiveInteger`) rejects an EMPTY field too, so blanking it would still block Save,
    /// contradicting the plan's own explicit "Save is never blocked" requirement — verified
    /// against Validators.swift, not assumed. Seeding the floor itself instead is the only value
    /// that satisfies both: it always passes validation (`number >= lastKnown`), and the field
    /// no longer carries the stale, sub-floor number the receipt printed. That number survives
    /// as a note rather than being silently discarded.
    func reconcileReceiptOdometerFloor() {
        guard wasReceiptSeeded else { return }
        defer { captureReceiptPrefillEffectiveSeed() }
        guard let floor = odometerFloor, let entered = Int(odometerReading), entered < floor else { return }
        odometerReading = String(floor)
        let floorNote = "Odometer on receipt: \(entered) mi"
        notes = notes.isEmpty ? floorNote : "\(notes)\n\n\(floorNote)"
        receiptPrefillSeededFields.insert(.notes)
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
