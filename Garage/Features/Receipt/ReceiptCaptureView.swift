import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The receipt sheet: photograph or import a receipt/invoice, Garage drafts an entry, then routes
/// to the matching form prefilled for the user to confirm. Unlike voice, this is NOT Pro-gated at
/// the entry point — a free user gets a lifetime teaser (plan §5); only quota exhaustion upsells.
struct ReceiptCaptureView: View {
    @Environment(AppRouter.self) var router // internal for the +Credits sibling file
    @Environment(AppState.self) private var appState
    // Internal for the +Credits sibling file.
    @State var viewModel = ReceiptCaptureViewModel()
    /// Created on first task (needs the environment's AppState for identity) — owns the
    /// credits top-up offer and the purchase->grant lifecycle.
    @State var credits: ReceiptCreditsController?
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImportingPDF = false

    var body: some View {
        BottomSheet(title: "Scan a Receipt") {
            content
            disclosureFooter
        }
        .task {
            // Controller setup + marker repair run BEFORE the quota refresh: the refresh's
            // sweepIncomplete loop is uncapped by contract, and awaiting it first would let a
            // stuck server flag starve paid-purchase repair forever (tri-review Sol r5).
            let controller = credits ?? ReceiptCreditsController(
                purchaser: ReceiptCreditsPurchaser(
                    store: ReceiptCreditsStoreClientFactory.make(),
                    markers: .shared,
                    currentUID: { [weak appState] in appState?.currentUserID }
                ),
                currentUID: { [weak appState] in appState?.currentUserID }
            )
            credits = controller
            // Marker repair BEFORE product availability: the offer cannot render until
            // availability is true, so Buy can never appear ahead of the resume pass's
            // unresolved-marker suppression (tri-review Sol r7).
            await controller.resumeOutstandingMarkers(recoveringInto: viewModel)
            await controller.refreshProductAvailability()
            await viewModel.refreshQuotaStatus()
        }
        .onChange(of: viewModel.proposal) { _, _ in
            if let package = viewModel.consumeProposalPackage() {
                router.presentReceiptPrefilledForm(package)
            }
        }
        .onDisappear {
            credits?.cancelActiveWork()
            viewModel.abandon()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onCapture: { data in
                    viewModel.addImage(data, source: .camera)
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await addLibraryPhoto(newValue) }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            viewModel.addPDF(url: url)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            pickerButtons
        case .preflighting:
            centeredStatus { ProgressView("Reading…") }
        case .ready:
            pagesSummary
            if viewModel.canAddImage || viewModel.canAddPDF { pickerButtons }
            if viewModel.canSubmit { confirmButton }
        case .parsing:
            centeredStatus {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Drafting your entry…").font(Theme.Typography.body)
                }
                .accessibilityElement(children: .combine)
            }
        case .failed(let failure):
            // Review finding: `.failed` used to be a dead end — no pickers/summary/confirm, so a
            // page-2 failure after page 1 already succeeded left dismissal (which wipes
            // imagePages) as the only exit, forcing a re-photograph and risking a second
            // unrefunded metered scan. Affordances stay reachable, mirroring VoiceQuickAddView
            // (the mic stays live through every phase): if a page survived, its summary and
            // pickers stay live; the view model alone decides whether another metered submit is
            // meaningful for the unchanged document.
            if viewModel.hasPages {
                pagesSummary
                if viewModel.canAddImage || viewModel.canAddPDF { pickerButtons }
                if viewModel.canSubmit { confirmButton }
            }
            failureView(failure)
        }
    }

    private func centeredStatus(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
    }

    private var pickerButtons: some View {
        HStack(spacing: Theme.Spacing.md) {
            if viewModel.canAddImage {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera.fill")
                    }
                    .accessibilityIdentifier("receipt.capture.camera")
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Library", systemImage: "photo")
                }
                .accessibilityIdentifier("receipt.capture.library")
            }
            if viewModel.canAddPDF {
                Button { isImportingPDF = true } label: {
                    Label("PDF", systemImage: "doc")
                }
                .accessibilityIdentifier("receipt.capture.pdf")
            }
        }
    }

    private var pagesSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let pdfPage = viewModel.pdfPage {
                pageRow(name: pdfPage.displayName, systemImage: "doc.fill") {
                    viewModel.removePDFPage()
                }
            }
            ForEach(Array(viewModel.imagePages.enumerated()), id: \.element.id) { index, page in
                pageRow(name: "Photo \(index + 1)", systemImage: "photo.fill") {
                    viewModel.removeImagePage(page.id)
                }
            }
        }
        .garageCard()
    }

    private func pageRow(name: String, systemImage: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage).foregroundStyle(Theme.Colors.textSecondary)
            Text(name).font(Theme.Typography.caption)
            Spacer()
            Button(role: .destructive, action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityLabel("Remove \(name)")
        }
        .frame(minHeight: 44)
    }

    private var confirmButton: some View {
        PrimaryButton(title: "Use This") {
            Task { await viewModel.confirmAndParse(vehicle: appState.currentVehicle) }
        }
        .accessibilityIdentifier("receipt.capture.confirm")
    }

    private var disclosureFooter: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let quotaFooterState = viewModel.quotaFooterState {
                Text(quotaFooterState.message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("receipt.capture.quota")
            }
            Text("Sent to Claude (Anthropic) to draft your entry. AI can make mistakes — "
                + "you review everything before saving.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func addLibraryPhoto(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            viewModel.addImage(data, source: .library)
        }
        selectedPhoto = nil
    }

    private static func resetText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func proMonthExhaustedMessage(_ resetAt: Date?) -> String {
        guard let resetAt else { return "You've used this month's receipt saves. Try again next month." }
        return "You've used this month's receipt saves. Resets " + resetText(resetAt) + "."
    }
}
