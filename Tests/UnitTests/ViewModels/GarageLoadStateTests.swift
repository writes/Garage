import Foundation
import Testing
@testable import Garage

/// Thrown by the loader seams below. File-scope rather than nested so it cannot pick up the test
/// suite's actor isolation.
private struct GarageLoadFailure: Error {}

/// The load state the five Garage screens now ladder on (loading → error → empty → content).
///
/// All four view models used to expose neither flag, so every screen branched to its empty state
/// purely on `.isEmpty`: the frame before the first fetch resolved read as "No records yet", and on
/// Detailing, Parts and Warranty a FAILED fetch read the same way forever — no error, no retry.
/// The third case in each group is the one that matters most: a failure must SETTLE (so the ladder
/// reaches the error banner) rather than leave the screen spinning.
@MainActor
struct GarageLoadStateTests {

    // MARK: - Detailing

    @Test func detailing_beforeAnyLoad_hasNotSettled() {
        let viewModel = DetailingViewModel(recordsLoader: { _ in [] })

        #expect(viewModel.hasCompletedFirstLoad == false)
        #expect(viewModel.isLoading == false)
    }

    @Test func detailing_afterASuccessfulLoad_settlesWithItsRecords() async {
        let viewModel = DetailingViewModel(recordsLoader: { _ in [Self.detailingRecord()] })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.records.count == 1)
        #expect(viewModel.error == nil)
    }

    @Test func detailing_afterAFailedLoad_settlesOnTheError() async {
        let viewModel = DetailingViewModel(recordsLoader: { _ in throw GarageLoadFailure() })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.error != nil)
        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
    }

    // MARK: - Spare parts

    @Test func parts_beforeAnyLoad_hasNotSettled() {
        let viewModel = PartsViewModel(partsLoader: { _ in [] })

        #expect(viewModel.hasCompletedFirstLoad == false)
        #expect(viewModel.isLoading == false)
    }

    @Test func parts_afterASuccessfulLoad_settlesWithItsParts() async {
        let viewModel = PartsViewModel(partsLoader: { _ in [Self.sparePart()] })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.parts.count == 1)
        #expect(viewModel.error == nil)
    }

    @Test func parts_afterAFailedLoad_settlesOnTheError() async {
        let viewModel = PartsViewModel(partsLoader: { _ in throw GarageLoadFailure() })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.error != nil)
        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
    }

    // MARK: - Gallery (backs both the photo and wheel screens)

    @Test func gallery_beforeAnyLoad_hasNotSettled() {
        let viewModel = GalleryViewModel(photosLoader: { _ in [] })

        #expect(viewModel.hasCompletedFirstLoad == false)
        #expect(viewModel.isLoading == false)
    }

    @Test func gallery_afterASuccessfulLoad_settlesWithItsPhotos() async {
        let viewModel = GalleryViewModel(photosLoader: { _ in [Self.galleryPhoto()] })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.photos.count == 1)
        #expect(viewModel.error == nil)
    }

    @Test func gallery_afterAFailedLoad_settlesOnTheError() async {
        let viewModel = GalleryViewModel(photosLoader: { _ in throw GarageLoadFailure() })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.error != nil)
        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
    }

    // MARK: - Warranty & recalls

    @Test func warranty_beforeAnyLoad_hasNotSettled() {
        let viewModel = WarrantyViewModel(contentLoader: { _ in .init(warranties: [], recalls: []) })

        #expect(viewModel.hasCompletedFirstLoad == false)
        #expect(viewModel.isLoading == false)
    }

    @Test func warranty_afterASuccessfulLoad_settlesWithBothRecordKinds() async {
        let viewModel = WarrantyViewModel(contentLoader: { _ in
            .init(warranties: [Self.warranty()], recalls: [Self.recall()])
        })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.warranties.count == 1)
        #expect(viewModel.recalls.count == 1)
        #expect(viewModel.error == nil)
    }

    @Test func warranty_afterAFailedLoad_settlesOnTheError() async {
        let viewModel = WarrantyViewModel(contentLoader: { _ in throw GarageLoadFailure() })

        await viewModel.load(vehicleId: "vehicle")

        #expect(viewModel.error != nil)
        #expect(viewModel.hasCompletedFirstLoad == true)
        #expect(viewModel.isLoading == false)
    }

    /// `checkForRecalls` reports through `isCheckingRecalls`, so it must not claim the screen has
    /// completed a load it never ran — the ladder would then show an empty list as confirmed.
    @Test func warranty_recallCheckDoesNotStandInForALoad() async {
        let viewModel = WarrantyViewModel(
            warrantyService: WarrantyService(testWarranties: [], testRecalls: []),
            recallLookup: FailingRecallLookup()
        )

        await viewModel.checkForRecalls(vehicle: Self.vehicle())

        #expect(viewModel.error != nil)
        #expect(viewModel.hasCompletedFirstLoad == false)
    }

    // MARK: - Fixtures

    private static func detailingRecord() -> DetailingRecord {
        DetailingRecord(
            id: "detailing-1", vehicleId: "vehicle", serviceDate: .now,
            serviceType: .wash, title: "Hand wash", attachmentPaths: []
        )
    }

    private static func sparePart() -> SparePart {
        SparePart(
            id: "part-1", vehicleId: "vehicle", name: "Track pads",
            category: .brakes, quantity: 1, condition: .new, isConsumed: false
        )
    }

    private static func galleryPhoto() -> GalleryPhoto {
        GalleryPhoto(
            id: "photo-1", vehicleId: "vehicle", title: "Front three-quarter",
            storagePath: "gallery/photo-1.jpg", includeInExport: true, displayOrder: 0, section: .main
        )
    }

    private static func warranty() -> Warranty {
        Warranty(id: "warranty-1", vehicleId: "vehicle", warrantyType: .factory, startDate: .now)
    }

    private static func recall() -> Recall {
        Recall(
            id: "recall-1", vehicleId: "vehicle", title: "Fuel pump",
            status: .outstanding, recallSource: .manual
        )
    }

    private static func vehicle() -> Vehicle {
        var vehicle = Vehicle.empty
        vehicle.id = "vehicle"
        vehicle.vin = nil
        return vehicle
    }
}

/// The VIN-missing path, which is also the `.validation` error the Warranty screen had no way to
/// render before this change.
private struct FailingRecallLookup: RecallLooking {
    func lookup(vin: String) async throws -> RecallLookupResponse {
        throw RecallLookupError.vinMissing
    }
}
