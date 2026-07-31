import Foundation
import Testing
@testable import Garage

/// The client half of the schemaVersion-2 wire contract (spec rev 3): server-shaped JSON →
/// proposal decode, including every tolerated degradation. The server's own tests pin the other
/// half; together they cover Sol #27's "server field accuracy does not prove Codable decoding".
struct TypedProposalDecodingTests {
    private func decodeVoice(_ json: String) throws -> VoiceEntryProposal {
        try JSONDecoder().decode(VoiceEntryProposal.self, from: Data(json.utf8))
    }

    @Test func v1ServerPayload_decodesWithAllNilTypedFields() throws {
        let proposal = try decodeVoice(#"""
        {"entryType":"fuel","odometerReading":62810,"cost":52,"shopName":"Shell",
         "isDiy":null,"entryDate":null,"notes":"fill up"}
        """#)
        #expect(proposal.entryType == .fuel)
        #expect(proposal.cost == 52)
        #expect(proposal.typed == .empty)
        #expect(proposal.typed.proposalSchemaVersion == nil)
    }

    @Test func v2Payload_decodesTypedFieldsFromTheSameFlatObject() throws {
        let proposal = try decodeVoice(#"""
        {"entryType":"tire","odometerReading":null,"cost":800,"shopName":"Discount Tire","isDiy":null,
         "entryDate":null,"notes":null,"workItem":null,"brand":"Michelin","productModel":"CrossClimate 2",
         "oilGrade":null,"quantityQuarts":null,"serviceAction":"new_install",
         "nextDueOdometer":null,"tireSizeFront":null,"tireSizeRear":null,"upgradeCategory":null,
         "proposalSchemaVersion":2}
        """#)
        #expect(proposal.typed.brand == "Michelin")
        #expect(proposal.typed.productModel == "CrossClimate 2")
        #expect(proposal.typed.serviceAction == "new_install")
        #expect(proposal.typed.proposalSchemaVersion == 2)
        #expect(proposal.typed.populatedFieldNames == ["brand", "productModel", "serviceAction"])
    }

    /// The core forward-compatibility guarantee (Sol #16 / Gemini #3): a future server enum
    /// value arrives as a plain string — it must decode, and the form-side rawValue conversion
    /// is what fails soft, not the decode.
    @Test func unknownEnumString_decodesAsARawString_neverThrows() throws {
        let proposal = try decodeVoice(
            #"{"entryType":"tire","serviceAction":"hover_conversion","proposalSchemaVersion":2}"#
        )
        #expect(proposal.typed.serviceAction == "hover_conversion")
        #expect(TireActionType(rawValue: proposal.typed.serviceAction ?? "") == nil)
    }

    /// A malformed typed value (wrong JSON type) degrades to "not extracted" for the typed
    /// block; the common proposal must survive untouched.
    @Test func malformedTypedValue_dropsTypedBlock_keepsCommonProposal() throws {
        let proposal = try decodeVoice(
            #"{"entryType":"tire","cost":800,"quantityQuarts":"five"}"#
        )
        #expect(proposal.entryType == .tire)
        #expect(proposal.cost == 800)
        #expect(proposal.typed == .empty)
    }

    @Test func receiptProposal_carriesTypedFieldsTheSameWay() throws {
        let proposal = try JSONDecoder().decode(ReceiptEntryProposal.self, from: Data(#"""
        {"entryType":"brake","cost":462.78,"shopName":"Meridian Auto Care",
         "lineItems":["Front brake pads & rotors — $286.00"],
         "serviceAction":"pads_replaced","proposalSchemaVersion":2}
        """#.utf8))
        #expect(proposal.lineItems == ["Front brake pads & rotors — $286.00"])
        #expect(proposal.typed.serviceAction == "pads_replaced")
    }

    @Test func explicitInit_defaultsTypedToEmpty_soExistingCallSitesCompileUnchanged() {
        let proposal = VoiceEntryProposal(entryType: .maintenance, cost: 40)
        #expect(proposal.typed == .empty)
    }
}

struct MaintenanceItemMatcherTests {
    @Test(arguments: [
        ("spark plugs replaced", MaintenanceItemKind.sparkPlugs),
        ("Cabin air filter", .cabinAirFilter),
        ("engine air filter", .airFilter),
        ("new wiper blades", .wiperBlades),
        ("coolant flush", .coolantFlush),
        ("brake fluid flush", .brakeFluidFlush),
        ("transmission fluid service", .transmissionService),
        ("differential service", .differentialService),
        ("serpentine belt", .beltsAndHoses),
        ("fuel injector cleaning", .fuelSystemService),
        ("rotate and balance", .rotateBalanceTires),
        ("battery swap", .batteryReplaced)
    ])
    func matches(text: String, expected: MaintenanceItemKind) {
        #expect(MaintenanceItemMatcher.match(text) == expected)
    }

    /// The specificity ordering that makes containment matching safe.
    @Test func cabinFilterNeverFallsThroughToEngineAirFilter() {
        #expect(MaintenanceItemMatcher.match("cabin air filter") == .cabinAirFilter)
        #expect(MaintenanceItemMatcher.match("brake fluid flush") == .brakeFluidFlush)
    }

    /// A miss returns nil — the picker keeps its default rather than guessing (rev-1 rule).
    @Test func unmatchedWorkItemReturnsNil() {
        #expect(MaintenanceItemMatcher.match("alternator replacement") == nil)
        #expect(MaintenanceItemMatcher.match("") == nil)
    }
}
