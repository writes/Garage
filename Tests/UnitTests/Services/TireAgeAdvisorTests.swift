import Foundation
import Testing
@testable import Garage

/// Age is the one tire fact the wear percentage cannot express, and it is also the one most likely
/// to be wrong in a way an owner would resent — nobody wants to be told their new tires are old.
/// Every ambiguous case here resolves to silence.
struct TireAgeAdvisorTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let year: TimeInterval = 365.25 * 24 * 60 * 60

    private func entry(
        _ type: EntryType, yearsAgo: Double, details: [String: AnyCodable] = [:]
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: UUID().uuidString, vehicleId: "v", userId: "u", entryType: type,
            entryDate: now.addingTimeInterval(-yearsAgo * year), odometerReading: 0, cost: nil,
            isDiy: nil, shopName: nil, notes: nil, attachmentPaths: [], isResolved: nil,
            details: details, createdAt: nil, updatedAt: nil
        )
    }

    private func tire(_ action: TireActionType, yearsAgo: Double) -> FirestoreEntry {
        entry(.tire, yearsAgo: yearsAgo, details: ["actionType": AnyCodable(action.rawValue)])
    }

    private func years(_ entries: [FirestoreEntry]) -> Double? {
        TireAgeAdvisor.yearsSinceNewInstall(entries: entries, now: now)
    }

    @Test func noInstallOnRecordSaysNothing() {
        #expect(years([]) == nil)
        #expect(years([entry(.oilChange, yearsAgo: 9)]) == nil)
    }

    /// A rotation moves the tires that are already on the car; a tread reading measures them; a
    /// removal takes them off. None of them is the day a new set went on, and dating rubber from
    /// any of them would age it from the wrong event.
    @Test func onlyANewInstallDatesTheRubber() {
        #expect(years([tire(.rotation, yearsAgo: 8)]) == nil)
        #expect(years([tire(.treadDepthReading, yearsAgo: 8)]) == nil)
        #expect(years([tire(.removed, yearsAgo: 8)]) == nil)
        #expect(years([tire(.newInstall, yearsAgo: 8)]) != nil)
    }

    /// FAILS CLOSED, unlike the rotation advisor. A tire entry with no readable action is no
    /// evidence that a new set went on, and reading it as one would date every owner's rubber from
    /// whichever record happened to be undecodable.
    @Test func anUnreadableTireEntryIsNotAnInstall() {
        #expect(years([entry(.tire, yearsAgo: 8)]) == nil)
        let unknown = [entry(.tire, yearsAgo: 8, details: ["actionType": AnyCodable("wheel_swap")])]
        #expect(years(unknown) == nil)
    }

    /// Below the threshold there is nothing worth saying, and saying it anyway would put a
    /// permanent caption under every tire row on the Dashboard.
    @Test func aFreshSetSaysNothing() {
        #expect(years([tire(.newInstall, yearsAgo: 0)]) == nil)
        #expect(years([tire(.newInstall, yearsAgo: 4.9)]) == nil)
    }

    @Test func fiveYearsIsTheThresholdAndItIsInclusive() {
        let atThreshold = years([tire(.newInstall, yearsAgo: 5)])
        #expect(atThreshold != nil)
        #expect(((atThreshold ?? 0) - 5).magnitude < 0.001)
    }

    @Test func anAgedSetReportsItsAge() {
        let age = years([tire(.newInstall, yearsAgo: 5.2)])
        #expect(((age ?? 0) - 5.2).magnitude < 0.001)
    }

    /// The LATEST install wins, which can only ever understate age — the conservative direction.
    /// A set fitted last year over one fitted eight years ago means the app says nothing rather
    /// than telling an owner their new rubber is ancient.
    @Test func theLatestInstallWins() {
        let entries = [tire(.newInstall, yearsAgo: 8), tire(.newInstall, yearsAgo: 6)]
        let age = years(entries)
        #expect(((age ?? 0) - 6).magnitude < 0.001)

        let replacedRecently = [tire(.newInstall, yearsAgo: 8), tire(.newInstall, yearsAgo: 1)]
        #expect(years(replacedRecently) == nil)
    }

    /// A typo'd entry date must not print a negative age. Nothing is younger than now.
    @Test func anInstallDatedInTheFutureSaysNothing() {
        #expect(years([tire(.newInstall, yearsAgo: -2)]) == nil)
    }

    /// The copy carries one decimal place: the install date is exact, so unlike the wear
    /// projection this figure is one the app can stand behind.
    @Test func theNoteStatesTheAgeToOneDecimalPlace() {
        let note = WearItemNote.tireAge(years: 5.24)
        #expect(note.text == "Installed 5.2 years ago — rubber ages even with tread left.")
        #expect(note.spoken.contains("5.2 years ago"))
        #expect(!note.spoken.contains("—"))
    }

    /// The projection note is approximate on its face, and its spoken form must not read "≈" aloud.
    @Test func theProjectionNoteIsExplicitlyApproximate() {
        let note = WearItemNote.projection(milesToReplacement: 4_200)
        #expect(note.text == "≈ 4,200 mi left at current rate")
        #expect(note.spoken == "About 4,200 miles left at the current rate")
    }

    /// Both axles carry the age note: there is one install date and no reliable per-axle scoping,
    /// so qualifying only one row would leave the other reading as unqualified good news.
    @Test func bothTireRowsAreEligibleForTheAgeNoteAndNoOtherRowIs() {
        #expect(WearItemType.frontTires.isTire)
        #expect(WearItemType.rearTires.isTire)
        for type in WearItemType.allCases where type != .frontTires && type != .rearTires {
            #expect(!type.isTire)
        }
    }
}
