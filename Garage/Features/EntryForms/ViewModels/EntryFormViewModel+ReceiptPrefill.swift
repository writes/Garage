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
        entryDate = proposal.resolvedDate(default: entryDate)
        if let odometer = proposal.odometerReading, odometer > 0 {
            odometerReading = String(odometer)
        }
        if let receiptCost = proposal.cost, receiptCost > 0 {
            cost = Self.costString(receiptCost)
        }
        if let shop = proposal.shopName?.trimmed, !shop.isEmpty {
            shopName = shop
            isDiy = false
        } else if let receiptIsDiy = proposal.isDiy {
            isDiy = receiptIsDiy
        }
        notes = Self.seededNotes(from: proposal)
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
        guard wasReceiptSeeded, let floor = odometerFloor,
              let entered = Int(odometerReading), entered < floor else { return }
        odometerReading = String(floor)
        let floorNote = "Odometer on receipt: \(entered) mi"
        notes = notes.isEmpty ? floorNote : "\(notes)\n\n\(floorNote)"
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
