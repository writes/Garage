import Foundation
import Testing
@testable import Garage

/// The wear pipeline was open at both ends before this: `WearService.saveSnapshots` had zero
/// callers and both forms hardcoded every wear field to nil, so the Dashboard wear section was
/// permanently empty in production and populated only by SeedData in demo mode. These tests pin
/// the mapping that closes it — especially the tread-depth scale, which is a safety judgement
/// rather than an arithmetic one.
struct WearSnapshotFactoryTests {
    private let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func brake(
        front: Double? = nil, rear: Double? = nil,
        frontRotor: Double? = nil, rearRotor: Double? = nil
    ) -> BrakeEntry {
        BrakeEntry(
            action: .padsReplaced, position: .all, padBrand: nil, padCompound: nil,
            rotorBrand: nil, padThicknessAtInstallMM: nil,
            frontPadPct: front, rearPadPct: rear,
            frontRotorPct: frontRotor, rearRotorPct: rearRotor, fluidFlushed: false
        )
    }

    private func tire(
        frontLeft: String? = nil, frontRight: String? = nil,
        rearLeft: String? = nil, rearRight: String? = nil
    ) -> TireEntry {
        TireEntry(
            actionType: .treadDepthReading, tireBrand: "B", tireModel: "M", tireSetId: nil,
            tireSizeFront: nil, tireSizeRear: nil, position: .allFour,
            treadDepthFL: frontLeft, treadDepthFR: frontRight,
            treadDepthRL: rearLeft, treadDepthRR: rearRight,
            heatCycles: nil, compound: nil, treadwearRating: nil
        )
    }

    private func brakeWrite(_ entry: BrakeEntry) -> WearSnapshotFactory.WearWrite {
        WearSnapshotFactory.write(
            from: entry, vehicleId: "v", entryId: "e",
            odometerReading: 50_000, recordedAt: recordedAt
        )
    }

    private func tireWrite(_ entry: TireEntry) -> WearSnapshotFactory.WearWrite {
        WearSnapshotFactory.write(
            from: entry, vehicleId: "v", entryId: "e",
            odometerReading: 50_000, recordedAt: recordedAt
        )
    }

    private func makeBrakeSnapshots(_ entry: BrakeEntry) -> [WearSnapshot] {
        brakeWrite(entry).snapshots
    }

    private func makeTireSnapshots(_ entry: TireEntry) -> [WearSnapshot] {
        tireWrite(entry).snapshots
    }

    // MARK: - Brakes

    @Test func aBrakeEntryWithNoReadingsProducesNothing() {
        #expect(makeBrakeSnapshots(brake()).isEmpty)
    }

    @Test func eachSuppliedBrakeReadingBecomesItsOwnSnapshot() {
        let snapshots = makeBrakeSnapshots(brake(front: 80, rear: 60, frontRotor: 90, rearRotor: 70))
        #expect(snapshots.count == 4)
        #expect(Set(snapshots.map(\.wearItem)) == [.frontBrakePads, .rearBrakePads, .frontRotors, .rearRotors])
    }

    @Test func aPartiallyFilledBrakeEntryOnlyRecordsWhatWasMeasured() {
        let snapshots = makeBrakeSnapshots(brake(front: 45))
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.wearItem == .frontBrakePads)
        #expect(snapshots.first?.valuePct == 45)
        #expect(snapshots.first?.valueRaw == "45%")
    }

    @Test func outOfRangeBrakePercentagesAreClamped() {
        #expect(makeBrakeSnapshots(brake(front: 140)).first?.valuePct == 100)
        #expect(makeBrakeSnapshots(brake(front: -20)).first?.valuePct == 0)
    }

    @Test func snapshotsCarryTheOdometerAndEntryTheyCameFrom() {
        let snapshot = makeBrakeSnapshots(brake(front: 50)).first
        #expect(snapshot?.odometerReading == 50_000)
        #expect(snapshot?.entryId == "e")
        #expect(snapshot?.vehicleId == "v")
        #expect(snapshot?.recordedAt == recordedAt)
    }

    // MARK: - Tread depth scale

    /// The safety-critical rule: percentage is measured against the USABLE range (10/32 down to
    /// the 2/32 legal minimum), not against zero. A tire at the legal limit must read 0%, not 20%.
    @Test func treadAtTheLegalMinimumReadsAsZeroPercent() {
        #expect(WearSnapshotFactory.treadPercentage(from: "2/32") == 0)
    }

    @Test func newTreadReadsAsOneHundredPercent() {
        #expect(WearSnapshotFactory.treadPercentage(from: "10/32") == 100)
    }

    @Test func halfwayThroughTheUsableRangeReadsAsFiftyPercent() {
        #expect(WearSnapshotFactory.treadPercentage(from: "6/32") == 50)
    }

    @Test func treadBelowTheLegalMinimumClampsToZeroRatherThanGoingNegative() {
        #expect(WearSnapshotFactory.treadPercentage(from: "1/32") == 0)
    }

    @Test func treadAboveNewClampsToOneHundred() {
        #expect(WearSnapshotFactory.treadPercentage(from: "12/32") == 100)
    }

    @Test func treadAcceptsTheThreeWaysPeopleWriteIt() {
        #expect(WearSnapshotFactory.parseTread32nds("6") == 6)
        #expect(WearSnapshotFactory.parseTread32nds("6/32") == 6)
        #expect(WearSnapshotFactory.parseTread32nds("6.5") == 6.5)
        #expect(WearSnapshotFactory.parseTread32nds(" 6 ") == 6)
    }

    @Test func unparseableTreadIsIgnoredRatherThanRecordedAsZero() {
        #expect(WearSnapshotFactory.parseTread32nds("plenty") == nil)
        #expect(WearSnapshotFactory.treadPercentage(from: "") == nil)
        #expect(makeTireSnapshots(tire(frontLeft: "plenty", frontRight: "also fine")).isEmpty)
    }

    // MARK: - Tires

    /// An axle is only as good as its most worn tire. Averaging would hide one bald corner behind
    /// a healthy one — the exact case a wear display exists to catch.
    @Test func anAxleReportsItsWorstCornerNotTheAverage() {
        let snapshots = makeTireSnapshots(tire(frontLeft: "9/32", frontRight: "3/32"))
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.wearItem == .frontTires)
        // 3/32 -> (3-2)/8 * 100 = 12.5%, not the 62.5% an average would give.
        #expect(snapshots.first?.valuePct == 12.5)
        #expect(snapshots.first?.valueRaw == "3/32")
    }

    @Test func frontAndRearAxlesAreRecordedSeparately() {
        let snapshots = makeTireSnapshots(
            tire(frontLeft: "8/32", frontRight: "8/32", rearLeft: "4/32", rearRight: "4/32")
        )
        #expect(snapshots.count == 2)
        let byType = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.wearItem, $0.valuePct) })
        #expect(byType[.frontTires] == 75)
        #expect(byType[.rearTires] == 25)
    }

    @Test func oneMeasuredCornerIsEnoughToRecordThatAxle() {
        let snapshots = makeTireSnapshots(tire(frontLeft: "8/32"))
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.wearItem == .frontTires)
    }

    @Test func aTireEntryWithNoReadingsProducesNothing() {
        #expect(makeTireSnapshots(tire()).isEmpty)
    }

    @Test func fractionalTreadKeepsItsPrecisionInTheRawLabel() {
        #expect(makeTireSnapshots(tire(frontLeft: "6.5")).first?.valueRaw == "6.5/32")
    }

    // MARK: - Crash and duplication defects found by adversarial review

    /// `Double("1e400")` is `+infinity`, and `infinity >= 0` is TRUE — so a plain non-negative
    /// check let it reach `Int(_:)`, which TRAPS and takes the app down. The decimal keypad can
    /// also produce a 25-digit number, which overflows Int64 by itself.
    @Test func absurdTreadInputIsRejectedRatherThanCrashingTheApp() {
        #expect(WearSnapshotFactory.parseTread32nds("1e400") == nil)
        #expect(WearSnapshotFactory.parseTread32nds("9999999999999999999999999") == nil)
        #expect(WearSnapshotFactory.parseTread32nds("-1e400") == nil)
        // And the whole pipeline survives it, which is the property that actually matters.
        #expect(makeTireSnapshots(tire(frontLeft: "1e400", frontRight: "99999999999999999999")).isEmpty)
    }

    @Test func treadExactlyAtThePlausibilityBoundIsStillAccepted() {
        #expect(WearSnapshotFactory.parseTread32nds("100") == 100)
        #expect(WearSnapshotFactory.parseTread32nds("101") == nil)
    }

    /// min/max with NaN silently return the other operand, so an unguarded NaN would be stored as
    /// a genuine 0%-remaining reading — the app telling someone their pads are gone.
    @Test func aNonFiniteBrakePercentageIsNotRecordedAsZeroPercent() {
        let write = brakeWrite(brake(front: .nan, rear: .infinity))
        #expect(write.snapshots.isEmpty)
    }

    /// Ids were fresh UUIDs, so every edit of the same entry appended ANOTHER wear document rather
    /// than replacing the original — unbounded growth, and two snapshots sharing one recordedAt
    /// where the dashboard's "latest wins" tiebreak could restore the value just corrected.
    @Test func reSavingTheSameEntryProducesTheSameSnapshotIDs() {
        let first = brakeWrite(brake(front: 80)).snapshots.map(\.id)
        let second = brakeWrite(brake(front: 40)).snapshots.map(\.id)
        #expect(first == second)
        #expect(first == [WearSnapshotFactory.snapshotID(entryID: "e", item: .frontBrakePads)])
    }

    @Test func snapshotIDsAreDistinctPerWearItem() {
        let ids = brakeWrite(brake(front: 80, rear: 60, frontRotor: 90, rearRotor: 70)).snapshots.map(\.id)
        #expect(Set(ids).count == 4)
    }

    /// Editing an entry to REMOVE a reading must delete the snapshot it created, or the dashboard
    /// keeps showing a value the user explicitly cleared.
    @Test func aClearedReadingIsMarkedForDeletionNotLeftBehind() {
        let write = brakeWrite(brake(front: 80))
        #expect(write.snapshots.count == 1)
        #expect(write.clearedIDs.count == 3)
        #expect(write.clearedIDs.contains(WearSnapshotFactory.snapshotID(entryID: "e", item: .rearBrakePads)))
        #expect(!write.clearedIDs.contains(WearSnapshotFactory.snapshotID(entryID: "e", item: .frontBrakePads)))
    }

    @Test func aClearedTireAxleIsMarkedForDeletion() {
        let write = tireWrite(tire(frontLeft: "8/32"))
        #expect(write.snapshots.map(\.wearItem) == [.frontTires])
        #expect(write.clearedIDs == [WearSnapshotFactory.snapshotID(entryID: "e", item: .rearTires)])
    }

    @Test func anEntryWithNoReadingsAtAllClearsEveryItemItCouldHaveWritten() {
        #expect(brakeWrite(brake()).clearedIDs.count == 4)
        #expect(tireWrite(tire()).clearedIDs.count == 2)
    }
}
