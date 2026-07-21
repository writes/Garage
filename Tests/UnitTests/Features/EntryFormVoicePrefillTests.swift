import Foundation
import Testing
@testable import Garage

@MainActor
struct EntryFormVoicePrefillTests {
    private func proposal(
        odometer: Int? = nil, cost: Double? = nil, shopName: String? = nil,
        isDiy: Bool? = nil, notes: String? = nil
    ) -> VoiceEntryProposal {
        VoiceEntryProposal(
            entryType: .maintenance, odometerReading: odometer, cost: cost,
            shopName: shopName, isDiy: isDiy, entryDate: nil, notes: notes
        )
    }

    @Test func prefillWithShopClearsDiyAndFillsCommonFields() {
        let viewModel = EntryFormViewModel()
        viewModel.applyVoicePrefill(proposal(
            odometer: 18_120, cost: 165, shopName: "  Willow Springs  ", isDiy: true, notes: " Mobil 1 "
        ))

        #expect(viewModel.odometerReading == "18120")
        #expect(viewModel.cost == "165")
        #expect(viewModel.shopName == "Willow Springs")
        #expect(viewModel.isDiy == false)
        #expect(viewModel.notes == "Mobil 1")
    }

    @Test func prefillHonorsDiyWhenNoShopSpoken() {
        let viewModel = EntryFormViewModel()
        viewModel.applyVoicePrefill(proposal(isDiy: true))
        #expect(viewModel.isDiy == true)
        #expect(viewModel.shopName.isEmpty)
    }

    @Test func prefillFormatsFractionalCostAndKeepsWholeClean() {
        let whole = EntryFormViewModel()
        whole.applyVoicePrefill(proposal(cost: 200))
        #expect(whole.cost == "200")

        let fractional = EntryFormViewModel()
        fractional.applyVoicePrefill(proposal(cost: 89.99))
        #expect(fractional.cost == "89.99")
    }

    @Test func prefillIgnoresNonPositiveNumbers() {
        let viewModel = EntryFormViewModel()
        viewModel.applyVoicePrefill(proposal(odometer: 0, cost: 0))
        #expect(viewModel.odometerReading.isEmpty)
        #expect(viewModel.cost.isEmpty)
    }
}
