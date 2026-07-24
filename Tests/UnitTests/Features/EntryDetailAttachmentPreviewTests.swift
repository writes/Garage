import Testing
@testable import Garage

/// Covers two confirmed QuickLook preview races fixed by hoisting download/temp-file ownership
/// from AttachmentDetailRow (now a dumb row) up into EntryDetailView (the sheet owner):
/// (a) concurrent PDF taps each downloading independently, racing PDFPreviewTempFile.write's
/// shared-temp-dir wipe against a live QuickLook sheet; (b) a late-arriving download from an
/// abandoned tap reopening a sheet the user already dismissed. EntryDetailView's @State-driven
/// logic isn't reachable from a test without a UI-hosting harness, so the pure decision points
/// are exposed as static functions — this covers those directly.
@MainActor
struct EntryDetailAttachmentPreviewTests {
    @Test func shouldStartPreviewDownload_trueWhenNothingIsInFlight() {
        #expect(EntryDetailView.shouldStartPreviewDownload(tappedPath: "a.pdf", inFlightPath: nil))
    }

    @Test func shouldStartPreviewDownload_falseForADuplicateTapOnTheSamePath() {
        #expect(!EntryDetailView.shouldStartPreviewDownload(tappedPath: "a.pdf", inFlightPath: "a.pdf"))
    }

    @Test func shouldStartPreviewDownload_falseForATapOnADifferentPathWhileAnotherIsInFlight() {
        #expect(!EntryDetailView.shouldStartPreviewDownload(tappedPath: "b.pdf", inFlightPath: "a.pdf"))
    }

    @Test func shouldApplyPreviewResult_trueWhenTheCompletedPathIsStillTheInFlightOne() {
        #expect(EntryDetailView.shouldApplyPreviewResult(for: "a.pdf", inFlightPath: "a.pdf"))
    }

    /// Race (b): the in-flight slot was cleared (by a dismissal, or — since only one download can
    /// ever be in flight at a time — moved to a new path) since this download started.
    @Test func shouldApplyPreviewResult_falseOnceTheInFlightSlotHasMovedOnOrCleared() {
        #expect(!EntryDetailView.shouldApplyPreviewResult(for: "a.pdf", inFlightPath: nil))
        #expect(!EntryDetailView.shouldApplyPreviewResult(for: "a.pdf", inFlightPath: "b.pdf"))
    }
}
