import Foundation

/// The schemaVersion-2 type-specific extraction fields, shared by voice and receipt proposals.
/// Spec: docs/research/2026-07-31_TYPED_EXTRACTION_SPEC.md (rev 3).
///
/// Every field is the RAW wire type — `String?`/`Double?`/`Int?` — never a Swift enum: a future
/// server enum value must decode to a value this build ignores, not throw away the whole payload
/// (review finding, both providers independently). Each form converts through an explicit table
/// (`FuelType.init(rawValue:)`, `TirePosition` tables, …) that fails soft to the form's default.
///
/// Decoded from the SAME flat JSON object as the proposal it belongs to (all keys top-level on
/// the wire). Against a v1 server every field is nil and `proposalSchemaVersion` is nil — an
/// all-nil value is indistinguishable from "nothing extracted" by design; the version marker is
/// what tells those apart for logging.
struct TypedProposalDetails: Codable, Equatable, Sendable {
    let workItem: String?
    let brand: String?
    let productModel: String?
    let oilGrade: String?
    let quantityQuarts: Double?
    let serviceAction: String?
    let nextDueOdometer: Int?
    let tireSizeFront: String?
    let tireSizeRear: String?
    let upgradeCategory: String?
    let proposalSchemaVersion: Int?

    static let empty = TypedProposalDetails(
        workItem: nil, brand: nil, productModel: nil, oilGrade: nil,
        quantityQuarts: nil,
        serviceAction: nil, nextDueOdometer: nil, tireSizeFront: nil, tireSizeRear: nil,
        upgradeCategory: nil, proposalSchemaVersion: nil
    )

    /// Names of the populated fields — the privacy-safe breadcrumb payload (names, never values).
    var populatedFieldNames: [String] {
        var names: [String] = []
        if workItem != nil { names.append("workItem") }
        if brand != nil { names.append("brand") }
        if productModel != nil { names.append("productModel") }
        if oilGrade != nil { names.append("oilGrade") }
        if quantityQuarts != nil { names.append("quantityQuarts") }
        if serviceAction != nil { names.append("serviceAction") }
        if nextDueOdometer != nil { names.append("nextDueOdometer") }
        if tireSizeFront != nil { names.append("tireSizeFront") }
        if tireSizeRear != nil { names.append("tireSizeRear") }
        if upgradeCategory != nil { names.append("upgradeCategory") }
        return names
    }
}
