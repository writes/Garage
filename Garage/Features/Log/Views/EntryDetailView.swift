import SwiftUI

struct EntryDetailView: View {
    let entry: FirestoreEntry
    private let entryService: EntryService
    private let entryAttachmentService: EntryAttachmentService

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deletionError: AppError?
    @State private var previewItem: PDFPreviewItem?
    /// The attachment path currently downloading for preview, if any — at most one at a time.
    /// Review fix (concurrent-tap race): a second tap while a download is already in flight is
    /// ignored rather than starting a second download that would race PDFPreviewTempFile.write's
    /// shared-temp-dir wipe against whatever the first tap's live QuickLook sheet is rendering.
    @State private var inFlightPreviewPath: String?
    @State private var previewErrorsByPath: [String: AppError] = [:]

    init(
        entry: FirestoreEntry,
        entryService: EntryService = .shared,
        entryAttachmentService: EntryAttachmentService = .shared
    ) {
        self.entry = entry
        self.entryService = entryService
        self.entryAttachmentService = entryAttachmentService
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                EntryRowView(entry: entry)
                ForEach(entry.details.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key.humanizedFieldLabel)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text((entry.details[key]?.value ?? .null).displayString)
                            .font(Theme.Typography.body)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !entry.attachmentPaths.isEmpty {
                    attachmentsSection
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle(entry.entryType.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("entry.detail.delete")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    // Same "present the next sheet, then dismiss this one" ordering
                    // presentVoicePrefilledForm uses when VoiceQuickAddView hands off to a form.
                    router.presentEditForm(for: entry)
                    dismiss()
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("entry.detail.edit")
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                Task { await deleteEntry() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this record. This cannot be undone.")
        }
        .alert(
            "Could Not Delete Entry",
            isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
        ) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError?.errorDescription ?? "Please try again.")
        }
        // This view owns the download/temp-write/preview lifecycle for every attachment row
        // (loadPreview below) so there's exactly one sheet/one temp-file/one in-flight-download
        // owner for the whole screen, regardless of how many attachment rows exist — rows
        // themselves are dumb (AttachmentDetailRow.swift). The onChange below (not a trailing
        // `onDismiss:` closure — swiftlint's multiple_closures_with_trailing_closure forbids two
        // trailing closures on one call) clears the temp file on both swipe-to-dismiss and the
        // "Done" button, since either path sets previewItem back to nil.
        .sheet(item: $previewItem) { item in
            NavigationStack {
                QuickLookPreview(url: item.url)
                    .navigationTitle(item.filename)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { previewItem = nil }
                                .accessibilityIdentifier("entry.detail.attachment.preview.done")
                        }
                    }
            }
        }
        .onChange(of: previewItem) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                PDFPreviewTempFile.removeAll()
                // Review fix (late-arrival race): a download that was still in flight when the
                // user dismissed must not be allowed to reopen the sheet once it finally
                // completes — see loadPreview's inFlightPreviewPath guard below.
                inFlightPreviewPath = nil
            }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Attachments")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(entry.attachmentPaths, id: \.self) { path in
                AttachmentDetailRow(
                    path: path,
                    entryAttachmentService: entryAttachmentService,
                    isLoading: inFlightPreviewPath == path,
                    previewError: previewErrorsByPath[path],
                    onTap: { attachmentTapped(path: path) }
                )
            }
        }
    }

    /// Ignored (not queued/replaced) if a download for ANY path — same or different — is already
    /// in flight: exactly one preview download at a time keeps PDFPreviewTempFile's single shared
    /// temp slot race-free.
    private func attachmentTapped(path: String) {
        guard Self.shouldStartPreviewDownload(tappedPath: path, inFlightPath: inFlightPreviewPath) else { return }
        inFlightPreviewPath = path
        previewErrorsByPath[path] = nil
        Task { await loadPreview(path: path) }
    }

    private func loadPreview(path: String) async {
        defer {
            if inFlightPreviewPath == path { inFlightPreviewPath = nil }
        }
        do {
            let data = try await entryAttachmentService.downloadData(for: path)
            let filename = (path as NSString).lastPathComponent
            let url = try PDFPreviewTempFile.write(data, filename: filename)
            // Late-arrival guard: only honor this download if the user hasn't already dismissed
            // (or otherwise moved past) it — see the onChange(of: previewItem) handler above.
            guard Self.shouldApplyPreviewResult(for: path, inFlightPath: inFlightPreviewPath) else { return }
            previewItem = PDFPreviewItem(id: path, url: url, filename: filename)
        } catch {
            guard Self.shouldApplyPreviewResult(for: path, inFlightPath: inFlightPreviewPath) else { return }
            previewErrorsByPath[path] = AppError(from: error)
        }
    }

    private func deleteEntry() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            // Attachment cascade lives at the SERVICE layer now (EntryService+Mutations.swift's
            // cascadeDeleteAttachments) — review BLOCKER: a view-layer-only cascade here missed
            // LogView's swipe-delete, which calls deleteEntry directly. Do not re-add a cascade
            // call here; there must be exactly one cascade site.
            try await entryService.deleteEntry(entry, updatingVehicle: appState.currentVehicle)
            dismiss()
        } catch {
            deletionError = AppError(from: error)
        }
    }
}

extension EntryDetailView {
    /// Whether a tap on `tappedPath` should start a new download. Pure/static and exposed for
    /// direct unit testing — a SwiftUI View's @State-driven logic otherwise isn't reachable from
    /// a test without a UI-hosting harness. Mirrors ReminderNotificationCoordinator.plan's
    /// "exposed for testing" precedent.
    static func shouldStartPreviewDownload(tappedPath: String, inFlightPath: String?) -> Bool {
        inFlightPath == nil
    }

    /// Whether a just-completed download for `path` should still be applied (set `previewItem`
    /// or surface its error). False once the in-flight slot has moved on — cleared either by a
    /// later dismissal or, since only one download can ever be in flight, never by another tap —
    /// so a late-arriving download from an abandoned tap can't reopen a sheet the user already
    /// dismissed.
    static func shouldApplyPreviewResult(for path: String, inFlightPath: String?) -> Bool {
        inFlightPath == path
    }
}
