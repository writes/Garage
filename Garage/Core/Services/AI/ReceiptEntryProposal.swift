import Foundation

/// A prefill proposal produced by the receiptQuickAdd Cloud Function from a photographed/imported
/// receipt. It is a SUGGESTION only — the UI presents it in the entry form for the user to
/// confirm/edit/save (Trust Pledge). Exactly `VoiceEntryProposal`'s shape plus `lineItems`, which
/// is joined into notes client-side (EntryFormViewModel+ReceiptPrefill.swift).
struct ReceiptEntryProposal: Codable, Equatable, Sendable {
    let entryType: EntryType
    let odometerReading: Int?
    let cost: Double?
    let shopName: String?
    let isDiy: Bool?
    /// ISO 8601 string, or nil meaning "today".
    let entryDate: String?
    let notes: String?
    let lineItems: [String]?
    /// schemaVersion-2 typed fields; all-nil against a v1 server. Decoded from the SAME flat
    /// object (the wire has no nesting) — mirrors VoiceEntryProposal's custom Codable.
    let typed: TypedProposalDetails

    init(
        entryType: EntryType,
        odometerReading: Int? = nil,
        cost: Double? = nil,
        shopName: String? = nil,
        isDiy: Bool? = nil,
        entryDate: String? = nil,
        notes: String? = nil,
        lineItems: [String]? = nil,
        typed: TypedProposalDetails = .empty
    ) {
        self.entryType = entryType
        self.odometerReading = odometerReading
        self.cost = cost
        self.shopName = shopName
        self.isDiy = isDiy
        self.entryDate = entryDate
        self.notes = notes
        self.lineItems = lineItems
        self.typed = typed
    }

    private enum CodingKeys: String, CodingKey {
        case entryType, odometerReading, cost, shopName, isDiy, entryDate, notes, lineItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryType = try container.decode(EntryType.self, forKey: .entryType)
        odometerReading = try container.decodeIfPresent(Int.self, forKey: .odometerReading)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        shopName = try container.decodeIfPresent(String.self, forKey: .shopName)
        isDiy = try container.decodeIfPresent(Bool.self, forKey: .isDiy)
        entryDate = try container.decodeIfPresent(String.self, forKey: .entryDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        lineItems = try container.decodeIfPresent([String].self, forKey: .lineItems)
        typed = (try? TypedProposalDetails(from: decoder)) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entryType, forKey: .entryType)
        try container.encodeIfPresent(odometerReading, forKey: .odometerReading)
        try container.encodeIfPresent(cost, forKey: .cost)
        try container.encodeIfPresent(shopName, forKey: .shopName)
        try container.encodeIfPresent(isDiy, forKey: .isDiy)
        try container.encodeIfPresent(entryDate, forKey: .entryDate)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(lineItems, forKey: .lineItems)
        try typed.encode(to: encoder)
    }
}
