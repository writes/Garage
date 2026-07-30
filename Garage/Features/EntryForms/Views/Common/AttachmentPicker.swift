import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Real attachments pipeline (external audit's top product-truth gap: "attachments retain
/// filenames rather than evidence"). Picking here only queues bytes locally
/// (EntryFormViewModel.addPendingImage/addPendingPDF) — nothing reaches Storage until the entry
/// is actually saved (see EntryFormViewModel+Attachments.swift's uploadPendingAttachments,
/// called from save()). EntryFormScaffold hides this entire section in demo/UI-test mode (no real
/// Storage there) and behind the Pro gate otherwise — EntryCreateJourneyTests
/// .testFuelEntryFormRetainsSaveAndHidesAttachmentPersistenceUI pins the demo-mode absence,
/// including these exact button/label strings.
struct AttachmentPicker: View {
    @Bindable var viewModel: EntryFormViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImportingPDF = false
    @State private var pickerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Attachments")
                .font(Theme.Typography.headline)

            HStack {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Add Photo", systemImage: "photo")
                }
                Button {
                    isImportingPDF = true
                } label: {
                    Label("Add PDF", systemImage: "doc")
                }
            }

            if viewModel.attachmentPaths.isEmpty && viewModel.pendingAttachments.isEmpty {
                Text("Receipts, invoices, and related photos show up here after selection.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(viewModel.attachmentPaths, id: \.self, content: uploadedRow)
                ForEach(viewModel.pendingAttachments, content: pendingRow)
            }

            if let pickerError {
                Text(pickerError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityIdentifier("entry.form.attachments.error")
            }
        }
        .garageCard()
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await addPhoto(newValue) }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task { await addPDF(from: url) }
        }
    }

    private func uploadedRow(_ path: String) -> some View {
        attachmentRow(
            systemImage: path.hasSuffix(".pdf") ? "doc.fill" : "photo.fill",
            name: (path as NSString).lastPathComponent
        ) {
            Button(role: .destructive) {
                viewModel.queueAttachmentRemoval(path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityLabel("Remove attachment")
        }
    }

    private func pendingRow(_ pending: PendingAttachment) -> some View {
        attachmentRow(
            systemImage: pending.kind == .pdf ? "doc.fill" : "photo.fill",
            name: pending.displayName
        ) {
            if viewModel.uploadingAttachmentID == pending.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(role: .destructive) {
                    viewModel.removePendingAttachment(pending.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("Remove \(pending.displayName)")
            }
        }
    }

    private func attachmentRow(
        systemImage: String, name: String, @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(name)
                .font(Theme.Typography.caption)
                .lineLimit(1)
            Spacer()
            trailing()
        }
        .frame(minHeight: 44)
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        pickerError = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let downsampled = await Self.downsampleJPEG(from: data) else {
            pickerError = "Could not read that photo. Try a different one."
            selectedPhoto = nil
            return
        }
        viewModel.addPendingImage(downsampled)
        selectedPhoto = nil
    }

    /// Off the main thread, like readPDFData below and OilAnalysisPDFPreflighter before it: a
    /// full-resolution camera capture is decoded, re-rendered at 2048pt and JPEG-encoded here, and
    /// running that on the main actor froze the form mid-pick for as long as it took. The photo
    /// path was the odd one out — the PDF path in this same file was already detached.
    private static func downsampleJPEG(from data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            AttachmentImageProcessor.downsampledJPEG(from: data)
        }.value
    }

    /// Security-scoped access is opened here (main actor) and held open via `defer` across the
    /// `await` below — readPDFData runs off the main thread (Task.detached, mirroring
    /// OilAnalysisPDFPreflighter's pattern) but operates on the same URL, so the access must stay
    /// open for the whole call, not just the synchronous part.
    private func addPDF(from url: URL) async {
        pickerError = nil
        guard url.startAccessingSecurityScopedResource() else {
            pickerError = "Could not access that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        switch await Self.readPDFData(from: url, maxBytes: Constants.maxAttachmentBytes) {
        case .success(let data):
            viewModel.addPendingPDF(data, filename: url.lastPathComponent)
        case .failure(.tooLarge):
            pickerError = "That PDF is larger than 20 MB. Choose a smaller file."
        case .failure(.unreadable):
            pickerError = "Could not read that PDF."
        }
    }

    /// Checks the file's reported size BEFORE reading any bytes (so an oversized pick fails fast
    /// without ever loading it into memory), then reads off the main thread.
    private static func readPDFData(from url: URL, maxBytes: Int) async -> Result<Data, PDFReadFailure> {
        await Task.detached(priority: .userInitiated) { () -> Result<Data, PDFReadFailure> in
            guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return .failure(.unreadable)
            }
            guard fileSize <= maxBytes else { return .failure(.tooLarge) }
            guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
            return .success(data)
        }.value
    }

    private enum PDFReadFailure: Error {
        case tooLarge
        case unreadable
    }
}
